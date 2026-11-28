model_matrix_for <- function(model, newdata) {
  predictor_terms <- delete.response(terms(model))
  frame <- model.frame(
    predictor_terms,
    data = newdata,
    xlev = model$xlevels,
    na.action = na.pass
  )
  matrix <- model.matrix(predictor_terms, frame, contrasts.arg = model$contrasts)
  coefficient_names <- names(coef(model))
  if (!setequal(colnames(matrix), coefficient_names)) {
    stop("Invalid contrast or design matrix.")
  }
  matrix[, coefficient_names, drop = FALSE]
}

replace_contrast_value <- function(dataset, variable, value) {
  changed <- dataset
  if (is.factor(dataset[[variable]])) {
    value <- as.character(value)
    if (!value %in% levels(dataset[[variable]])) {
      stop("Invalid contrast or design matrix.")
    }
    changed[[variable]] <- factor(
      rep(value, nrow(dataset)),
      levels = levels(dataset[[variable]]),
      ordered = is.ordered(dataset[[variable]])
    )
  } else {
    value <- as.numeric(value)
    if (length(value) != 1L || !is.finite(value)) {
      stop("Invalid contrast or design matrix.")
    }
    changed[[variable]] <- rep(value, nrow(dataset))
  }
  changed
}

compute_standardized_contrast <- function(model, evaluation_data, variable, low, high) {
  low_data <- replace_contrast_value(evaluation_data, variable, low)
  high_data <- replace_contrast_value(evaluation_data, variable, high)
  low_matrix <- model_matrix_for(model, low_data)
  high_matrix <- model_matrix_for(model, high_data)
  coefficients <- coef(model)
  covariance <- vcov(model)

  mean_difference <- colMeans(high_matrix - low_matrix)
  log_or <- as.numeric(crossprod(mean_difference, coefficients))
  log_or_variance <- as.numeric(t(mean_difference) %*% covariance %*% mean_difference)
  if (!is.finite(log_or_variance) || log_or_variance <= 0) {
    stop("Invalid contrast or design matrix.")
  }
  log_or_se <- sqrt(log_or_variance)
  log_or_p <- 2 * pnorm(abs(log_or / log_or_se), lower.tail = FALSE)

  low_probability <- plogis(as.vector(low_matrix %*% coefficients))
  high_probability <- plogis(as.vector(high_matrix %*% coefficients))
  probability_difference <- mean(high_probability - low_probability)
  probability_gradient <- colMeans(
    high_probability * (1 - high_probability) * high_matrix -
      low_probability * (1 - low_probability) * low_matrix
  )
  probability_variance <- as.numeric(t(probability_gradient) %*% covariance %*% probability_gradient)
  if (!is.finite(probability_variance) || probability_variance <= 0) {
    stop("Invalid contrast or design matrix.")
  }
  probability_se <- sqrt(probability_variance)

  list(
    log_or = log_or,
    OR = exp(log_or),
    lower = exp(log_or - qnorm(0.975) * log_or_se),
    upper = exp(log_or + qnorm(0.975) * log_or_se),
    p = log_or_p,
    probability_difference = probability_difference,
    probability_lower = probability_difference - qnorm(0.975) * probability_se,
    probability_upper = probability_difference + qnorm(0.975) * probability_se,
    probability_p = 2 * pnorm(abs(probability_difference / probability_se), lower.tail = FALSE)
  )
}

lrt <- function(smaller, larger) anova(smaller, larger, test="LRT")[2,"Pr(>Chi)"]
gvif <- function(fit) {
  terms <- attr(terms(fit), "term.labels")
  if (anyNA(coef(fit))) return(setNames(rep(NA_real_, length(terms)), terms))
  v <- car::vif(fit)
  setNames(v[, "GVIF"], rownames(v))
}
infer <- function(d) {
  linear <- study_formula()
  spline <- study_formula(2)
  fits <- list(M1=fit_logit(linear,d), M2=fit_logit(spline,d),
               M3L=fit_logit(linear,d,TRUE), M3S=fit_logit(spline,d,TRUE))
  base <- fits$M1
  full_design <- update(linear, . ~ . + Department + factor(JobLevel))
  expanded <- model.matrix(full_design, d)
  # This linear combination of two indicators isolates an all-stayer cell.
  hr_direction <- as.integer(d$Department == "Human Resources") - as.integer(d$JobRole == "Human Resources")
  stopifnot(all(hr_direction >= 0), any(hr_direction > 0), all(d$Attrition[hr_direction > 0] == 0))
  hr_cell <- c(records=sum(hr_direction > 0), departures=sum(d$Attrition[hr_direction > 0]))
  level_only <- glm(update(linear, . ~ . + factor(JobLevel)), d, family=binomial())
  v <- gvif(base)
  cols <- attr(terms(full_design), "term.labels")
  diagnostics <- data.frame(term=cols, before="Undefined (separation)",
                            without_department=unname(gvif(level_only)[cols]), final=unname(v[cols]))
  interval <- function(fit, variable) {
    x <- d[[variable]]
    limits <- if (is.factor(x)) c(levels(x)[1],tail(levels(x),1)) else quantile(x,c(.25,.75))
    e <- compute_standardized_contrast(fit,d,variable,limits[1],limits[2])
    data.frame(variable, low=as.character(limits[1]), high=as.character(limits[2]),
               OR=e$OR, OR_lo=e$lower, OR_hi=e$upper, delta=e$probability_difference,
               delta_lo=e$probability_lower,delta_hi=e$probability_upper,p=e$p)
  }
  hypotheses <- c(continuous[1:5],"JobSatisfaction","EnvironmentSatisfaction","OverTime")
  contrasts <- do.call(rbind,lapply(names(fits), function(m) {
    z <- do.call(rbind,lapply(hypotheses, function(v) interval(fits[[m]],v)))
    transform(z, model=m, Holm=p.adjust(p,"holm"))
  }))
  small <- fit_logit(update(linear,. ~ . - YearsInCurrentRole - YearsWithCurrManager - YearsSinceLastPromotion), d)
  tenure <- do.call(rbind,lapply(list(reduced=small,full=base),function(f)
    data.frame(beta=unname(coef(f)["YearsAtCompany"]),SE=unname(sqrt(diag(vcov(f)))["YearsAtCompany"]),
               GVIF=unname(gvif(f)["YearsAtCompany"]),delta=interval(f,"YearsAtCompany")$delta)))
  curvature <- sapply(continuous,function(v) lrt(fit_logit(study_formula(2,setdiff(continuous,v)),d),fits$M2))
  interactions <- c(overtime_balance=lrt(base,fit_logit(update(linear,. ~ . + OverTime:WorkLifeBalance),d)),
                    tenure_promotion=lrt(base,fit_logit(update(linear,. ~ . + YearsAtCompany:YearsSinceLastPromotion),d)))
  roles <- as.data.frame.matrix(table(d$JobRole,d$Attrition))
  names(roles) <- c("stayed","left")
  precision <- do.call(rbind,lapply(names(fits),function(m) {
    se <- sqrt(diag(vcov(fits[[m]])))
    se <- se[startsWith(names(se),"JobRole")]
    role <- sub("^JobRole","",names(se))
    data.frame(model=m,role,events=roles[role,"left"],SE=unname(se),width=2*qnorm(.975)*unname(se))
  }))
  smooth3 <- fit_logit(study_formula(3),d)
  cook <- cooks.distance(base)
  sensitivity <- fit_logit(linear,d[cook <= 4/nrow(d),])
  list(fits=fits, diagnostics=diagnostics, rank=c(qr(expanded)$rank,ncol(expanded)),hr_cell=hr_cell,
       contrasts=contrasts,tenure=tenure,curvature=p.adjust(curvature,"holm"),
       global=lrt(base,fits$M2), df3=c(AIC(smooth3),smooth3$rank), interactions=p.adjust(interactions,"holm"),
       roles=roles,precision=precision,cook_n=sum(cook > 4/nrow(d)),
       sensitivity=interval(sensitivity,"OverTime"))
}
