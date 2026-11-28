models <- c("Base","M1","M2","M3L","M3S","Ridge","EN")
ranking <- function(y,p) {
  o <- order(p,decreasing=TRUE)
  last <- !duplicated(p[o], fromLast=TRUE)
  tp <- cumsum(y[o])[last]; n <- seq_along(y)[last]
  data.frame(recall=c(0,tp/sum(y)), fpr=c(0,(n-tp)/sum(1-y)), precision=c(1,tp/n))
}
cal_curve <- function(y,p,grid=p) {
  if (length(unique(p)) == 1) return(rep(mean(y),length(grid)))
  fit <- loess(y ~ p, span=.75, degree=1, control=loess.control(surface="direct"))
  inside <- grid >= min(p) & grid <= max(p)
  result <- rep(NA_real_,length(grid))
  result[inside] <- pmin(1,pmax(0,predict(fit,data.frame(p=grid[inside]))))
  result
}
metrics <- function(y,p) {
  r <- ranking(y,p)
  lp <- qlogis(bound(p))
  intercept <- unname(coef(glm(y ~ 1 + offset(lp),family=binomial()))[1])
  slope <- if (length(unique(p)) > 1) unname(coef(glm(y ~ lp,family=binomial()))[2]) else NA_real_
  c(AUC=sum(diff(r$fpr)*(head(r$recall,-1)+tail(r$recall,-1))/2),
    AP=sum(diff(r$recall)*tail(r$precision,-1)), Brier=mean((y-p)^2),
    LogLoss=mean(loss(y,p)), Intercept=intercept,Slope=slope, ICI=mean(abs(cal_curve(y,p)-p)))
}
thresholds <- (5:50)/100
benefit <- function(y,p,t) mean((p >= t)*(y - (1-y)*t/(1-t)))
evaluate <- function(oof) {
  scores <- dplyr::bind_rows(lapply(split(oof,interaction(oof$rep,oof$fold)), function(z)
    dplyr::bind_rows(lapply(models,function(m)
      data.frame(rep=z$rep[1],fold=z$fold[1],model=m,as.list(metrics(z$y,z[[m]])))))))
  by_rep <- split(oof,oof$rep)
  curves <- dplyr::bind_rows(lapply(by_rep,function(z) dplyr::bind_rows(lapply(setdiff(models,"Base"),function(m) {
    p <- z[[m]]; y <- z$y; r <- ranking(y,p)
    grid <- 0:100/100
    data.frame(model=m,rep=z$rep[1],grid,
               ROC=approx(r$fpr,r$recall,xout=grid,ties=max)$y,
               PR=vapply(grid,function(k) r$precision[which(r$recall>=k)[1]],numeric(1)),
               Calibration=cal_curve(y,p,grid))
  }))))
  dca <- dplyr::bind_rows(lapply(by_rep,function(z) dplyr::bind_rows(lapply(c(setdiff(models,"Base"),"All","None"),function(m) {
    p <- switch(m, All=rep(1,nrow(z)),None=rep(0,nrow(z)),z[[m]])
    data.frame(model=m,rep=z$rep[1],threshold=thresholds,
               NB=vapply(thresholds,function(t) benefit(z$y,p,t),numeric(1)))
  }))))
  list(scores=scores,curves=curves,dca=dca)
}
