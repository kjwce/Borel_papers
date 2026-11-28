# Reproduce the IBM attrition study

The manuscript source is [logit1.rmd](../../logit/logit1.rmd). The [rendered article](../../logit/logit.html) embeds its four figures. The [research brief](gop-y-trien-khai-nghien-cuu.md) records the original specification.

From the repository root, create an R environment and render the article.

```sh
micromamba create -y -n borel-logit --override-channels -c conda-forge \
  r-base=4.5 r-rmarkdown r-knitr r-car r-brglm2 r-detectseparation r-glmnet r-ggplot2 \
  r-patchwork r-dplyr r-tidyr pandoc
cd logit
OPENBLAS_NUM_THREADS=1 micromamba run -n borel-logit Rscript \
  -e 'rmarkdown::render("logit1.rmd", output_file="logit.html")'
```

The render needs network access to the pinned IBM CSV. It verifies the downloaded bytes before reading the 1,470 records. All numerical analyses run again on each render. The software versions used for the published HTML appear at the end of the article. Expect two diagnostic warnings from sensitivity fits, described in Results.

To inspect numerical results interactively, start R in the `logit` directory and run either analysis after loading its source.

```r
source("study-design.R")
d <- load_ibm()

source("inference.R")
a <- infer(d)
a$tenure

source("prediction.R")
source("evaluation.R")
oof <- outer_predictions(d)
evaluation <- evaluate(oof)
table(oof$rep, oof$fold)
head(evaluation$scores)
```

The predictions keep the input row index, repeat, outer fold, training prevalence, fitted probabilities and selected penalty parameters. One full run produces 14,700 held-out rows and 350 fold-by-method score records. Exported PNGs are in [logit/figures](../../logit/figures/).
