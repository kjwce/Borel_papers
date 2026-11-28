# Construct validation designs from the analysis split's fitted spline terms.
split_design <- function(train, test, formula) {
  for (v in categorical) {
    unseen <- setdiff(unique(as.character(test[[v]])), unique(as.character(train[[v]])))
    if (length(unseen)) stop("Unseen assessment levels for ", v, ": ", paste(unseen, collapse=", "))
  }
  frame <- model.frame(formula, train)
  terms <- delete.response(attr(frame, "terms"))
  list(x=model.matrix(terms, frame)[,-1,drop=FALSE],
       newx=model.matrix(terms, model.frame(terms, test))[,-1,drop=FALSE])
}
folds <- function(d) {
  group <- integer(nrow(d))
  for (rows in split(seq_len(nrow(d)), d$Attrition))
    group[rows] <- sample(rep_len(1:5, length(rows)))
  group
}
alphas <- c(0,.25,.5,.75,1)
lambdas <- exp(seq(log(1), log(.0001), length.out=55))
path_prob <- function(design, y, alpha) {
  fit <- glmnet::glmnet(design$x, y, family="binomial", alpha=alpha, lambda=lambdas,
                        standardize=TRUE)
  stopifnot(fit$jerr == 0, length(fit$lambda) == length(lambdas))
  as.matrix(predict(fit, newx=design$newx, type="response"))
}
bound <- function(p) pmin(pmax(p, 1e-15), 1-1e-15)
loss <- function(y,p) -(y*log(bound(p)) + (1-y)*log1p(-bound(p)))
tuned_prob <- function(train, test) {
  inner <- folds(train)
  scores <- matrix(0, length(lambdas), length(alphas))
  for (k in 1:5) {
    train_k <- train[inner != k,]
    test_k <- train[inner == k,]
    design <- split_design(train_k, test_k, study_formula(2))
    for (a in seq_along(alphas)) {
      p <- path_prob(design, train_k$Attrition, alphas[a])
      scores[,a] <- scores[,a] + colSums(loss(test_k$Attrition,p))
    }
  }
  best <- arrayInd(which.min(scores), dim(scores))
  design <- split_design(train, test, study_formula(2))
  ridge <- path_prob(design, train$Attrition, 0)
  elastic <- if (best[2] == 1) ridge else path_prob(design, train$Attrition, alphas[best[2]])
  list(ridge=ridge[,which.min(scores[,1])], elastic=elastic[,best[1]],
       alpha=alphas[best[2]], lambda=lambdas[best[1]], ridge_lambda=lambdas[which.min(scores[,1])])
}
separated <- function(fit) {
  diagnostic <- detectseparation::detect_separation(
    x=model.matrix(fit), y=fit$y, family=binomial(),
    control=list(implementation="lpSolveAPI", linear_program="dual", purpose="test")
  )
  stopifnot(is.logical(diagnostic$outcome), length(diagnostic$outcome) == 1L, !is.na(diagnostic$outcome))
  diagnostic$outcome
}
outer_predictions <- function(d) {
  set.seed(20261108)
  splits <- replicate(10, folds(d))
  parts <- list()
  for (r in 1:10) for (k in 1:5) {
    held <- splits[,r] == k
    train <- d[!held,]; test <- d[held,]
    tuned <- tuned_prob(train, test)
    fits <- lapply(list(M1=c(1,0), M2=c(2,0), M3L=c(1,1), M3S=c(2,1)), function(spec) {
      fit_logit(study_formula(spec[1]), train, spec[2] == 1)
    })
    estimates <- lapply(fits, function(fit) unname(predict(fit, test, type="response")))
    parts[[length(parts)+1L]] <- data.frame(rep=r, fold=k, row=which(held), y=test$Attrition,
      Base=mean(train$Attrition), estimates, Ridge=tuned$ridge, EN=tuned$elastic,
      separated_M1=separated(fits$M1), separated_M2=separated(fits$M2),
      alpha=tuned$alpha, lambda=tuned$lambda, ridge_lambda=tuned$ridge_lambda)
  }
  out <- do.call(rbind, parts)
  stopifnot(all(table(out$row,out$rep) == 1), length(unique(interaction(out$rep,out$fold))) == 50,
            all(is.finite(as.matrix(out))))
  out
}
