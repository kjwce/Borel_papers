# Independent review of the IBM attrition study

29 November 2026. A reviewer used a separate Git clone on the same Linux host and the same R environment. The review compared the [research brief](../../docs/logit/gop-y-trien-khai-nghien-cuu.md), [manuscript source](../../logit/logit1.rmd), R implementations and [HTML](../../logit/logit.html). The [reproduction guide](../../docs/logit/reproduce-logit.md) gives the render command and input source.

| Check | Evidence |
|---|---|
| Manuscript scope | Six English sections within their specified word ranges, four numbered result tables and four exported 300 dpi figures. |
| Data and resampling | 1,470 synthetic profiles, 237 departures. Each profile appeared once in assessment in each of ten repeats. Fifty outer folds yielded 14,700 held-out rows and 350 model-by-fold score records. The baseline used training prevalence. |
| Independent numerical checks | Separately computed AUC and AP agreed for all 350 records. Direct counts of true and false alerts reproduced DCA, including the two ridge superiority ranges on the specified grid. |
| Full-sample separation | Eleven HR-department managers stayed and none left. A contrast of the department and role indicators isolates this cell. The expanded model has full matrix rank but no finite ordinary MLE. The revised Table 1 marks coefficient-based GVIFs undefined at this step. |
| Outer-fold separation | Independent linear programs checked 100 outer training designs and three full-sample designs. In repeat 10, fold 4, both departing research directors were held out. Linear and spline ordinary fits on that training set returned numerical stopping-rule iterates. Table 4 retains all folds. |
| Sensitivity to the separated fold | Mean paired ridge-minus-M2 log-loss was −0.007420 across 50 folds and −0.005418 across the other 49. Ridge reduced loss on 31/50 and 30/49 folds, respectively. |

The reviewer rechecked the separation disclosures, existence diagnostics, manuscript equations, sources and quantitative claims after revision. This is an internal reproducibility check on a fixed synthetic dataset.

The final clean-clone render matched the delivered HTML and all four 300 dpi PNGs byte for byte. HTML SHA-256 was `248363cc513a30bc1ad5a3b9a234905326aefa8db265ef0264e98ad04cd25fe0`. All 100 outer ordinary fits and their separation diagnostics also ran with warnings promoted to errors. Final review found no remaining blockers.
