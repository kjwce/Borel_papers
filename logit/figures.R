library(ggplot2)
make_figures <- function(d,a,e) {
  theme_set(theme_bw(base_size=11) + theme(legend.position="bottom"))
  v <- "MonthlyIncome"
  grid <- seq(quantile(d[[v]],.025),quantile(d[[v]],.975),length.out=80)
  profiles <- dplyr::bind_rows(lapply(c("M1","M2","M3S"),function(m) {
    p <- vapply(grid,function(x) mean(predict(a$fits[[m]],replace_contrast_value(d,v,x),type="response")),numeric(1))
    data.frame(income=grid,model=m,p)
  }))
  f1 <- ggplot(profiles,aes(income,p,colour=model)) + geom_line() +
    geom_rug(data=d,aes(x=MonthlyIncome),inherit.aes=FALSE,alpha=.07) +
    labs(x="Monthly income (dataset units)",y="Standardized attrition probability",colour="Model")
  precision <- subset(a$precision,events <= 5)
  precision <- tidyr::pivot_longer(precision,c("SE","width"),names_to="measure")
  f2 <- ggplot(precision,aes(model,value,colour=role,shape=role)) + geom_point(size=3) +
    facet_wrap(~measure,scales="free_y",labeller=as_labeller(c(SE="Standard error",width="95% Wald interval width"))) +
    labs(x="Estimator",y="Log-odds units",colour="Role",shape="Role")
  curves <- tidyr::pivot_longer(e$curves,c("ROC","PR","Calibration"),names_to="panel")
  curves <- dplyr::summarise(dplyr::group_by(curves,panel,model,grid),
                             n=sum(is.finite(value)),avg=mean(value,na.rm=TRUE),
                             lo=if (n) min(value,na.rm=TRUE) else NA_real_,
                             hi=if (n) max(value,na.rm=TRUE) else NA_real_,.groups="drop")
  curves <- subset(curves,n==10)
  draw <- function(which_panel,x,y) {
    ggplot(subset(curves,curves$panel == which_panel),aes(grid,avg,colour=model)) +
      geom_ribbon(aes(ymin=lo,ymax=hi,fill=model),colour=NA,alpha=.075) +
      geom_line() + labs(x=x,y=y,colour="Model",fill="Model") +
      coord_cartesian(xlim=c(0,1),ylim=c(0,1))
  }
  roc <- draw("ROC","False-positive rate","True-positive rate") + geom_abline(linetype=3)
  pr <- draw("PR","Recall","Precision") + geom_hline(yintercept=mean(d$Attrition),linetype=3)
  cal <- draw("Calibration","Predicted probability","Observed proportion (LOESS)") + geom_abline(linetype=3)
  f3 <- patchwork::wrap_plots(roc,pr,cal,nrow=1,guides="collect") & theme(legend.position="bottom")
  nb <- aggregate(NB ~ model + threshold,e$dca,mean)
  f4 <- ggplot(nb,aes(threshold,NB,colour=model,linetype=model %in% c("All","None"))) +
    geom_line(linewidth=.75) + scale_linetype_manual(values=c("solid","dashed"),guide="none") +
    coord_cartesian(ylim=c(-.03,max(nb$NB)*1.05)) +
    labs(x="Decision threshold",y="Net benefit per observation",colour="Strategy")
  dir.create("figures",showWarnings=FALSE)
  figures <- list(f1,f2,f3,f4)
  for (i in seq_along(figures))
    ggsave(sprintf("figures/figure-%d.png",i),figures[[i]],width=if (i==3) 12 else 8,
           height=if (i==3) 4.4 else 4.8,dpi=300,bg="white")
}
