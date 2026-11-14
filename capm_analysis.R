# CAPM trên dữ liệu Fama-French (R). Cần: tidyverse, lubridate, patchwork, scales, corrplot, zoo, lmtest, sandwich, modelsummary, car, tseries, FinTS, forecast

# ======== 2.1 Nguồn dữ liệu và nạp dữ liệu
library(tidyverse); library(lubridate)

path  <- "F-F_Research_Data_Factors_1.csv"
lines <- readLines(path, warn = FALSE)

# Ghi chú -> khối tháng -> khối năm
hdr <- which(startsWith(trimws(lines), ",Mkt-RF"))

read_block <- function(i) {
  blank <- which(trimws(lines) == "")
  end   <- blank[blank > i][1]
  if (is.na(end)) end <- length(lines) + 1
  read_csv(I(lines[(i + 1):(end - 1)]),
           col_names = c("period", "MktRF", "SMB", "HML", "RF"),
           show_col_types = FALSE)
}
m_raw <- read_block(hdr[1])
a_raw <- read_block(hdr[2])

cat(trimws(lines[1:3]), sep = "\n")
dim(m_raw); dim(a_raw)
head(m_raw); tail(m_raw)

# ======== 2.3 Kiểm tra chất lượng dữ liệu và làm sạch
m <- m_raw %>%
  mutate(date = ceiling_date(ymd(paste0(period, "01")), "month") - days(1))

# (a) Thiếu và mã thiếu
sum(is.na(m_raw)); sum(m_raw[c("MktRF", "SMB", "HML", "RF")] <= -99)
# (b) Trùng lặp
sum(duplicated(m$period))
# (c) Liên tục
full <- seq(floor_date(min(m$date), "month"), floor_date(max(m$date), "month"), by = "month")
cat(nrow(m), "tháng, kỳ vọng", length(full), "\n")
# (d) Miền hợp lý
sum(m$RF < 0)
m %>% summarise(across(c(MktRF, SMB, HML, RF), list(min = min, max = max)))

# (e) Đối chiếu khối năm
m <- m %>% mutate(Rm = MktRF + RF)
chk <- m %>% group_by(year = year(date)) %>%
  summarise(n = n(), Rm_c = (prod(1 + Rm / 100) - 1) * 100,
            RF_c = (prod(1 + RF / 100) - 1) * 100) %>%
  mutate(MktRF_c = Rm_c - RF_c) %>%
  inner_join(a_raw, by = c("year" = "period")) %>% filter(n == 12)
cat("Lệch tối đa Mkt-RF:", max(abs(chk$MktRF_c - chk$MktRF)),
    "| RF:", max(abs(chk$RF_c - chk$RF)), "\n")

# (f) Ngoại lai |z| > 3 (chỉ báo cáo)
z <- scale(m[c("MktRF", "SMB", "HML", "RF")])
colSums(abs(z) > 3)
m %>% slice_min(MktRF, n = 5) %>% select(date, MktRF)
m %>% slice_max(MktRF, n = 5) %>% select(date, MktRF)

# ======== 2.4 Kỹ thuật tạo biến và xuất dữ liệu sạch
capm <- m %>% select(date, MktRF, SMB, HML, RF) %>%
  mutate(
    Rm = MktRF + RF,
    lRm = log1p(Rm / 100) * 100, lRF = log1p(RF / 100) * 100, lMktRF = lRm - lRF,
    MktRF2 = MktRF^2, MktRF_lag1 = lag(MktRF),
    post1963 = as.integer(date >= as.Date("1963-07-01")),
    decade = year(date) %/% 10 * 10
  )

crisis <- tribble(~ten, ~from, ~to,
  "Đại suy thoái 1929-1932", "1929-09-01", "1932-06-30",
  "Khủng hoảng dầu 1973-1974", "1973-01-01", "1974-12-31",
  "Bong bóng dot-com 2000-2002", "2000-03-01", "2002-10-31",
  "Khủng hoảng tài chính 2007-2009", "2007-12-01", "2009-06-30",
  "COVID-19 2020", "2020-02-01", "2020-04-30") %>%
  mutate(across(c(from, to), as.Date))

capm$crisis <- as.integer(sapply(capm$date, function(d) any(d >= crisis$from & d <= crisis$to)))

capm <- capm %>% mutate(
  cum_Rm = cumprod(1 + Rm / 100), cum_RF = cumprod(1 + RF / 100),
  cum_SMB = cumprod(1 + SMB / 100), cum_HML = cumprod(1 + HML / 100),
  drawdown_Rm = (cum_Rm / cummax(cum_Rm) - 1) * 100,
  vol12_MktRF = zoo::rollapply(MktRF, 12, sd, fill = NA, align = "right") * sqrt(12),
  across(c(MktRF, SMB, HML), ~ as.integer(abs(scale(.)) > 3), .names = "out_{.col}")
)

dim(capm); sum(capm$crisis); min(capm$drawdown_Rm)
write_csv(capm, "capm_clean_monthly.csv")

# ======== 3.1 Bảng 1, 2, 3: thống kê mô tả, tương quan và lợi suất theo thập niên
vars_ <- c("MktRF", "SMB", "HML", "RF")
skew <- function(x) mean((x - mean(x))^3) / sd(x)^3
kurt <- function(x) mean((x - mean(x))^4) / sd(x)^4

t1 <- capm %>% summarise(across(all_of(vars_), list(
  n = ~sum(!is.na(.)), mean = mean, sd = sd, min = min, max = max,
  median = median, skew = skew, kurt = kurt), .names = "{.col}__{.fn}")) %>%
  pivot_longer(everything(), names_to = c("bien", ".value"), names_sep = "__") %>%
  mutate(mean_yr = mean * 12, vol_yr = sd * sqrt(12),
         sharpe = ifelse(bien == "RF", NA, mean_yr / vol_yr))
print(t1, width = Inf)

round(cor(capm[vars_]), 3)

capm %>% group_by(decade) %>%
  summarise(across(all_of(vars_), ~ round(mean(.), 2)), n_thang = n())

# ======== 3.2 Trực quan hóa dữ liệu
library(ggplot2); library(patchwork); library(scales)

# Hình 1
capm %>% select(date, Rm = cum_Rm, RF = cum_RF, SMB = cum_SMB, HML = cum_HML) %>%
  pivot_longer(-date, names_to = "chuoi", values_to = "gia_tri") %>%
  ggplot(aes(date, gia_tri, colour = chuoi, linetype = chuoi %in% c("SMB", "HML"))) +
  geom_line() + scale_y_log10(labels = label_comma()) +
  labs(title = "Hình 1. Giá trị tích lũy của 1 USD từ tháng 7/1926", y = "Thang log", x = NULL,
       colour = NULL, linetype = NULL) + theme_minimal()

# Hình 2
capm %>% select(all_of(vars_)) %>% pivot_longer(everything(), names_to = "bien", values_to = "x") %>%
  group_by(bien) %>% mutate(mu = mean(x), s = sd(x)) %>%
  ggplot(aes(x)) + geom_histogram(aes(y = after_stat(density)), bins = 55, fill = "#2b7bba") +
  geom_density(colour = "#d9534f", linetype = 2) +
  facet_wrap(~ bien, scales = "free") +
  labs(title = "Hình 2. Phân phối các chuỗi lợi suất tháng", x = "% mỗi tháng") + theme_minimal()

# Hình 3
p3a <- ggplot(capm, aes(date, MktRF)) +
  geom_rect(data = crisis, aes(xmin = from, xmax = to, ymin = -Inf, ymax = Inf),
            inherit.aes = FALSE, fill = "grey60", alpha = .3) +
  geom_line(linewidth = .3, colour = "#2b7bba") +
  labs(title = "Hình 3. Mkt-RF và biến động tụ cụm", y = "Mkt-RF (%/tháng)", x = NULL) + theme_minimal()
p3b <- ggplot(capm, aes(date, vol12_MktRF)) + geom_line(colour = "#d9534f") +
  labs(y = "Độ lệch chuẩn trượt 12 tháng", x = NULL) + theme_minimal()
p3a / p3b + plot_layout(heights = c(2, 1))

# Hình 4
library(corrplot)
corrplot(cor(capm[vars_]), method = "color", addCoef.col = "black", tl.col = "black")
capm %>% group_by(decade) %>% summarise(across(c(MktRF, SMB, HML), mean)) %>%
  pivot_longer(-decade, names_to = "chuoi", values_to = "tb") %>%
  ggplot(aes(factor(decade), tb, fill = chuoi)) + geom_col(position = "dodge") +
  labs(x = "Thập niên", y = "%/tháng") + theme_minimal()

# Hình 5
capm %>% select(MktRF, SMB, HML) %>% pivot_longer(-MktRF, names_to = "chuoi", values_to = "y") %>%
  ggplot(aes(MktRF, y)) + geom_point(alpha = .3, size = .8) +
  geom_smooth(method = "lm", colour = "#d9534f") + facet_wrap(~ chuoi) +
  labs(title = "Hình 5. SMB, HML và Mkt-RF") + theme_minimal()

# ======== 4.1 Thiết lập 5 mô hình thực nghiệm và bảng tổng hợp
library(lmtest); library(sandwich); library(modelsummary)

nw_lag <- function(T) floor(4 * (T / 100)^(2 / 9))
hac    <- function(m) NeweyWest(m, lag = nw_lag(nobs(m)), prewhite = FALSE, adjust = FALSE)

post <- subset(capm, date >= as.Date("1963-07-01"))
models <- list(
  M1 = lm(SMB ~ MktRF, data = capm),
  M2 = lm(HML ~ MktRF, data = capm),
  M3 = lm(SMB ~ MktRF, data = post),
  M4 = lm(HML ~ MktRF, data = post),
  M5 = lm(HML ~ MktRF + MktRF2, data = capm)
)

modelsummary(models, vcov = lapply(models, function(m) function(x) hac(m)),
             stars = c("*" = .1, "**" = .05, "***" = .01),
             gof_map = c("nobs", "r.squared", "adj.r.squared"),
             coef_rename = c("(Intercept)" = "alpha"))

sapply(models, function(m) dwtest(m)$statistic)

# ======== 5.1 Diễn giải alpha, beta và phần bù rủi ro thị trường
for (k in c("M1", "M2", "M3", "M4")) {
  m <- models[[k]]; ct <- coeftest(m, vcov = hac(m))
  cat(k, "alpha =", round(coef(m)[1], 4), "| alpha/năm =", round(12 * coef(m)[1], 2),
      "| t(HAC) =", round(ct[1, 3], 2), "| beta =", round(coef(m)[2], 3), "\n")
  print(coefci(m, vcov. = hac(m))[2, ])
}

# Phần bù rủi ro thị trường: hồi quy Mkt-RF lên hằng số
mp <- lm(MktRF ~ 1, data = capm)
coeftest(mp, vcov = hac(mp)); coef(mp) * 12
mean(capm$MktRF) / sd(capm$MktRF) * sqrt(12)

mp2 <- lm(MktRF ~ 1, data = post)
coeftest(mp2, vcov = hac(mp2))

coeftest(models$M5, vcov = hac(models$M5))

# ======== 5.2 Kiểm định đồng thời alpha bằng GRS và đường thị trường chứng khoán (SML)
grs <- function(df, assets, f = "MktRF") {
  T <- nrow(df); N <- length(assets)
  Y <- as.matrix(df[assets]); X <- cbind(1, df[[f]])
  B <- solve(t(X) %*% X, t(X) %*% Y); E <- Y - X %*% B
  Sig <- crossprod(E) / T; alpha <- B[1, ]
  mu <- mean(df[[f]]); Om <- mean((df[[f]] - mu)^2)
  stat <- (T - N - 1) / N * as.numeric(t(alpha) %*% solve(Sig, alpha)) / (1 + mu^2 / Om)
  c(F = stat, p = pf(stat, N, T - N - 1, lower.tail = FALSE), alpha = alpha)
}
grs(capm, c("SMB", "HML"))
grs(post,  c("SMB", "HML"))

# Hình 6: SML
prem <- mean(capm$MktRF)
pts <- tibble(
  ten  = c("Tín phiếu", "Thị trường", "SMB", "HML", "SMB (từ 1963)", "HML (từ 1963)"),
  beta = c(0, 1, coef(models$M1)[2], coef(models$M2)[2], coef(models$M3)[2], coef(models$M4)[2]),
  tb   = c(0, prem, mean(capm$SMB), mean(capm$HML), mean(post$SMB), mean(post$HML)))
ggplot(pts, aes(beta, tb, label = ten)) +
  geom_abline(slope = prem, intercept = 0) + geom_point(size = 3) + geom_text(vjust = -1) +
  labs(x = "Beta", y = "Lợi suất vượt trội trung bình (%/tháng)", title = "Hình 6. Đường SML") +
  theme_minimal()

# ======== 6.1 Đa cộng tuyến, phương sai sai số thay đổi, sai dạng hàm, phân phối của phần dư và tự tương quan
library(car); library(tseries); library(FinTS); library(forecast)

# 6.1 Đa cộng tuyến (chỉ M5 có hai biến giải thích)
vif(models$M5)
capm <- capm %>% mutate(MktRF_c = MktRF - mean(MktRF), MktRF_c2 = MktRF_c^2)
vif(lm(HML ~ MktRF_c + MktRF_c2, data = capm))

diag_all <- function(m) {
  c(BP     = bptest(m)$p.value,                          # Koenker
    RESET  = resettest(m, power = 2:3, type = "fitted")$p.value,
    JB     = jarque.bera.test(residuals(m))$p.value,
    DW     = unname(dwtest(m)$statistic),
    BG12   = bgtest(m, order = 12)$p.value,
    LB_e   = Box.test(residuals(m),   lag = 12, type = "Ljung-Box")$p.value,
    LB_e2  = Box.test(residuals(m)^2, lag = 12, type = "Ljung-Box")$p.value,
    ARCH12 = ArchTest(residuals(m), lags = 12)$p.value)
}
round(sapply(models[c("M1", "M2", "M3", "M4")], diag_all), 4)

# ======== 6.2 Điểm ảnh hưởng và đồ thị chẩn đoán
m2 <- models$M2
cd <- cooks.distance(m2); h <- hatvalues(m2)
sum(cd > 4 / nobs(m2)); sum(h > 2 * 2 / nobs(m2))
head(sort(cd, decreasing = TRUE), 5)
capm$date[order(cd, decreasing = TRUE)[1:5]]

e <- residuals(m2)
p1 <- ggplot(tibble(f = fitted(m2), e = e), aes(f, e)) + geom_point(alpha = .3) + geom_hline(yintercept = 0)
p2 <- ggplot(tibble(e = e), aes(sample = e)) + stat_qq() + stat_qq_line(colour = "red")
p3 <- ggAcf(e^2, lag.max = 36) + ggtitle("ACF của phần dư bình phương")   # forecast::ggAcf
p4 <- ggplot(tibble(date = capm$date, cd = cd), aes(date, cd)) + geom_col(width = 20) +
  geom_hline(yintercept = 4 / nobs(m2), colour = "red", linetype = 2)
(p1 + p2) / (p3 + p4)

# ======== 7.1 Độ bền vững với các đặc tả và mẫu khác
spec_rows <- function(asset) {
  q99 <- quantile(abs(capm$MktRF), .99)
  f <- as.formula(paste(asset, "~ MktRF"))
  one <- function(lab, d, form = f) {
    m <- lm(form, data = d); ct <- coeftest(m, vcov = hac(m))
    tibble(spec = lab, N = nobs(m), alpha = ct[1, 1], t_alpha = ct[1, 3],
           beta = ct[2, 1], t_beta = ct[2, 3], R2 = summary(m)$r.squared)
  }
  bind_rows(
    one("Toàn mẫu", capm), one("Từ 1963-07", post),
    one("Bỏ giai đoạn biến động lớn", filter(capm, crisis == 0)),
    one("Bỏ 1% tháng cực đoan", filter(capm, abs(MktRF) <= q99)))
}
spec_rows("SMB"); spec_rows("HML")

# Hiệu chỉnh Dimson
md <- lm(HML ~ MktRF + MktRF_lag1, data = capm)
linearHypothesis(md, "MktRF + MktRF_lag1 = 0", vcov. = hac(md))
sum(coef(md)[2:3])

# ======== 7.2 Tính ổn định của beta theo thời gian: các giai đoạn con, kiểm định Chow và beta trượt
periods <- list(c("1926-07-01", "1951-06-30"), c("1951-07-01", "1976-06-30"),
                c("1976-07-01", "2001-06-30"), c("2001-07-01", "2026-09-30"))
for (asset in c("SMB", "HML")) for (p in periods) {
  d <- filter(capm, date >= as.Date(p[1]), date <= as.Date(p[2]))
  m <- lm(as.formula(paste(asset, "~ MktRF")), d)
  print(c(asset, p[1], round(coeftest(m, vcov = hac(m))[, c(1, 3)], 3)))
}

# Kiểm định Chow qua mô hình có biến tương tác
chow <- function(asset, cuts) {
  g <- cut(as.numeric(capm$date), c(-Inf, as.numeric(as.Date(cuts)), Inf), labels = FALSE)
  r <- lm(as.formula(paste(asset, "~ MktRF")), capm)
  u <- lm(as.formula(paste(asset, "~ factor(g) * MktRF")), capm)
  anova(r, u)
}
chow("SMB", "1963-07-01"); chow("HML", "1963-07-01")
chow("HML", c("1951-07-01", "1976-07-01", "2001-07-01"))

# Beta trượt 60 tháng
roll_beta <- function(asset, w = 60)
  zoo::rollapply(capm[c(asset, "MktRF")], w, function(z) coef(lm(z[, 1] ~ z[, 2]))[2],
                 by.column = FALSE, fill = NA, align = "right")
capm$beta_SMB <- roll_beta("SMB"); capm$beta_HML <- roll_beta("HML")
capm %>% select(date, beta_SMB, beta_HML) %>% pivot_longer(-date) %>%
  ggplot(aes(date, value)) + geom_line() + facet_wrap(~ name, ncol = 1) +
  geom_hline(yintercept = 0) + labs(title = "Hình 8. Beta trượt 60 tháng") + theme_minimal()



