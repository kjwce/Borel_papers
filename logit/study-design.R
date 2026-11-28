# Read the checksum-verified public IBM release.
load_ibm <- function() {
  url <- paste0("https://raw.githubusercontent.com/IBM/employee-attrition-aif360/",
                "13287d5f717dc978eda249aef4665e04c7cec8b0/data/emp_attrition.csv")
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  download.file(url, path, mode = "wb", quiet = TRUE)
  stopifnot(unname(tools::md5sum(path)) == "ad8207459e5732574372cf8ff619883f")
  d <- read.csv(path, fileEncoding = "UTF-8-BOM")
  stopifnot(nrow(d) == 1470, ncol(d) == 35, !anyNA(d), !anyDuplicated(d$EmployeeNumber),
            setequal(d$Attrition, c("Yes","No")), sum(d$Attrition == "Yes") == 237,
            all(vapply(d[c("EmployeeCount","Over18","StandardHours")], function(x) length(unique(x)) == 1, logical(1))))
  d$Attrition <- as.integer(d$Attrition == "Yes")
  refs <- c(Gender="Female", MaritalStatus="Married", OverTime="No", JobRole="Healthcare Representative",
            JobSatisfaction="1", EnvironmentSatisfaction="1", BusinessTravel="Non-Travel",
            WorkLifeBalance="1", JobInvolvement="1", StockOptionLevel="0")
  for (v in names(refs)) d[[v]] <- relevel(factor(d[[v]]), refs[[v]])
  d
}
continuous <- c("Age","DistanceFromHome","MonthlyIncome","TotalWorkingYears","YearsAtCompany",
                "YearsInCurrentRole","YearsWithCurrManager","NumCompaniesWorked",
                "YearsSinceLastPromotion","TrainingTimesLastYear")
categorical <- c("Gender","MaritalStatus","OverTime","JobRole","JobSatisfaction",
                 "EnvironmentSatisfaction","BusinessTravel","WorkLifeBalance","JobInvolvement","StockOptionLevel")
study_formula <- function(df = 1, curved = continuous) {
  terms <- continuous
  if (df > 1) terms[terms %in% curved] <- sprintf("splines::ns(%s, df = %d)", curved, df)
  reformulate(c(terms, categorical), "Attrition")
}
fit_logit <- function(formula, d, firth = FALSE) {
  fit <- if (firth) glm(formula, data=d, family=binomial(), method=brglm2::brglmFit, type="AS_mean")
         else glm(formula, data=d, family=binomial())
  stopifnot(fit$converged, !anyNA(coef(fit)))
  fit
}
