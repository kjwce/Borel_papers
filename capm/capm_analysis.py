# -*- coding: utf-8 -*-
# CAPM trên dữ liệu Fama-French. Cần file F-F_Research_Data_Factors_1.csv cùng thư mục.

# ======== 2.1 Nguồn dữ liệu và nạp dữ liệu
import pandas as pd, numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats

sns.set_theme(style="whitegrid")
PATH = "F-F_Research_Data_Factors_1.csv"
lines = open(PATH, encoding="utf-8", errors="ignore").read().splitlines()

# File gồm vài dòng ghi chú, khối dữ liệu THÁNG, rồi khối dữ liệu NĂM
hdr = [i for i, l in enumerate(lines) if l.strip().startswith(",Mkt-RF")]

def read_block(i):
    rows = []
    for l in lines[i + 1:]:
        if not l.strip():
            break
        rows.append([x.strip() for x in l.split(",")])
    d = pd.DataFrame(rows, columns=["period", "MktRF", "SMB", "HML", "RF"])
    return d.apply(pd.to_numeric, errors="coerce")

m_raw, a_raw = read_block(hdr[0]), read_block(hdr[1])

print("Ghi chú đầu file:")
print("\n".join(l.strip() for l in lines[:3]))
print("\nKhối tháng:", m_raw.shape, "| khối năm:", a_raw.shape)
print("\n5 dòng đầu:");  print(m_raw.head().to_string(index=False))
print("\n5 dòng cuối:"); print(m_raw.tail().to_string(index=False))

# ======== 2.3 Kiểm tra chất lượng dữ liệu và làm sạch
m = m_raw.copy()

# (a) Giá trị thiếu. Dữ liệu Fama-French mã hóa thiếu bằng -99.99 hoặc -999
print("(a) NaN:", int(m.isna().sum().sum()),
      "| mã thiếu (<= -99):", int((m.drop(columns="period") <= -99).sum().sum()))

# (b) Trùng lặp
print("(b) Kỳ bị trùng:", int(m.period.duplicated().sum()))

# (c) Chuỗi thời gian có liên tục không?
m["date"] = pd.to_datetime(m.period.astype(int).astype(str), format="%Y%m") + pd.offsets.MonthEnd(0)
full = pd.period_range(m.date.min().to_period("M"), m.date.max().to_period("M"), freq="M")
missing_months = full.difference(m.date.dt.to_period("M"))
print(f"(c) {len(m)} tháng, kỳ vọng {len(full)}, thiếu {len(missing_months)} tháng "
      f"({m.date.min():%m/%Y} đến {m.date.max():%m/%Y})")

# (d) Miền giá trị hợp lý
print("(d) Số tháng có RF < 0:", int((m.RF < 0).sum()))
print(m[["MktRF", "SMB", "HML", "RF"]].agg(["min", "max"]).T.to_string())

# (e) Đối chiếu với khối dữ liệu NĂM trong cùng file
m["Rm"] = m.MktRF + m.RF
yr = m.groupby(m.date.dt.year)
chk = pd.DataFrame({"n": yr.size(),
                    "Rm_c": yr.Rm.apply(lambda s: (np.prod(1 + s / 100) - 1) * 100),
                    "RF_c": yr.RF.apply(lambda s: (np.prod(1 + s / 100) - 1) * 100)})
chk["MktRF_c"] = chk.Rm_c - chk.RF_c
a = a_raw.set_index("period")
ok = chk.index[(chk.n == 12) & chk.index.isin(a.index)]
d_mkt = (chk.loc[ok, "MktRF_c"] - a.loc[ok, "MktRF"]).abs()
d_rf = (chk.loc[ok, "RF_c"] - a.loc[ok, "RF"]).abs()
print(f"(e) Đối chiếu {len(ok)} năm đủ 12 tháng: lệch tối đa Mkt-RF = {d_mkt.max():.3f}, "
      f"RF = {d_rf.max():.3f} (điểm phần trăm)")

# (f) Ngoại lai theo z-score: chỉ báo cáo, KHÔNG xóa (đây là các cú sốc thật của thị trường)
cols = ["MktRF", "SMB", "HML", "RF"]
z = (m[cols] - m[cols].mean()) / m[cols].std()
print("(f) Số tháng có |z| > 3:", (z.abs() > 3).sum().to_dict())
print("\n5 tháng tệ nhất của Mkt-RF:");  print(m.nsmallest(5, "MktRF")[["date", "MktRF"]].to_string(index=False))
print("\n5 tháng tốt nhất của Mkt-RF:"); print(m.nlargest(5, "MktRF")[["date", "MktRF"]].to_string(index=False))

# ======== 2.4 Kỹ thuật tạo biến và xuất dữ liệu sạch
capm = m.drop(columns="period").set_index("date")[["MktRF", "SMB", "HML", "RF"]].copy()

# Lợi suất thị trường (chưa trừ lãi suất phi rủi ro) và dạng log
capm["Rm"]     = capm.MktRF + capm.RF
capm["lRm"]    = np.log1p(capm.Rm / 100) * 100
capm["lRF"]    = np.log1p(capm.RF / 100) * 100
capm["lMktRF"] = capm.lRm - capm.lRF

# Biến phục vụ mô hình mở rộng và kiểm tra khuyết tật
capm["MktRF2"]      = capm.MktRF ** 2                  # kiểm tra phi tuyến (Treynor-Mazuy)
capm["MktRF_lag1"]  = capm.MktRF.shift(1)              # hiệu chỉnh Dimson (giao dịch không đồng bộ)
capm["post1963"]    = (capm.index >= "1963-07-01").astype(int)   # mốc mẫu chuẩn của Fama-French
capm["decade"]      = (capm.index.year // 10 * 10).astype(int)

# Các giai đoạn biến động lớn (nhóm em tự định nghĩa theo mốc thời gian thường được nhắc tới)
crisis = {"Đại suy thoái 1929-1932": ("1929-09-01", "1932-06-30"),
          "Khủng hoảng dầu 1973-1974": ("1973-01-01", "1974-12-31"),
          "Bong bóng dot-com 2000-2002": ("2000-03-01", "2002-10-31"),
          "Khủng hoảng tài chính 2007-2009": ("2007-12-01", "2009-06-30"),
          "COVID-19 2020": ("2020-02-01", "2020-04-30")}
capm["crisis"] = 0
for a_, b_ in crisis.values():
    capm.loc[a_:b_, "crisis"] = 1

# Giá trị tích lũy của 1 USD, mức sụt giảm và biến động trượt 12 tháng
for v in ["Rm", "RF", "SMB", "HML"]:
    capm[f"cum_{v}"] = (1 + capm[v] / 100).cumprod()
capm["drawdown_Rm"] = (capm.cum_Rm / capm.cum_Rm.cummax() - 1) * 100
capm["vol12_MktRF"] = capm.MktRF.rolling(12).std() * np.sqrt(12)

# Cờ ngoại lai |z| > 3 (không xóa)
for v in ["MktRF", "SMB", "HML"]:
    capm[f"out_{v}"] = (((capm[v] - capm[v].mean()) / capm[v].std()).abs() > 3).astype(int)

print("Kích thước:", capm.shape, "| số tháng thuộc giai đoạn biến động lớn:", int(capm.crisis.sum()))
print("Số tháng từ 1963-07:", int(capm.post1963.sum()))
print("Mức sụt giảm sâu nhất của thị trường: %.1f%% (tháng %s)" %
      (capm.drawdown_Rm.min(), capm.drawdown_Rm.idxmin().strftime("%m/%Y")))
print("Giá trị cuối kỳ của 1 USD: thị trường = %.0f, tín phiếu = %.1f" % (capm.cum_Rm.iloc[-1], capm.cum_RF.iloc[-1]))
print("\nCác cột:", ", ".join(capm.columns))

capm.reset_index().to_csv("capm_clean_monthly.csv", index=False, encoding="utf-8")

# ======== 3.1 Bảng 1, 2, 3: thống kê mô tả, tương quan và lợi suất theo thập niên
vars_ = ["MktRF", "SMB", "HML", "RF"]

t1 = capm[vars_].agg(["count", "mean", "std", "min", "max"]).T
t1["median"] = capm[vars_].median()
t1["skew"]   = [stats.skew(capm[v]) for v in vars_]
t1["kurt"]   = [stats.kurtosis(capm[v], fisher=False) for v in vars_]   # độ nhọn (chuẩn = 3)
t1["mean_yr"] = t1["mean"] * 12
t1["vol_yr"]  = t1["std"] * np.sqrt(12)
t1["sharpe"]  = np.where(t1.index == "RF", np.nan, t1.mean_yr / t1.vol_yr)
print("Bảng 1: Thống kê mô tả (đơn vị %/tháng, riêng mean_yr và vol_yr là %/năm)")
print(t1.round(3).to_string())

print("\nBảng 2: Ma trận tương quan")
print(capm[vars_].corr().round(3).to_string())

print("\nBảng 3: Lợi suất trung bình theo thập niên (%/tháng)")
t3 = capm.groupby("decade")[vars_].mean().round(2)
t3["n_thang"] = capm.groupby("decade").size()
print(t3.to_string())

# ======== 3.2 Trực quan hóa dữ liệu
# Hình 1: giá trị tích lũy của 1 USD (thang log)
fig, ax = plt.subplots(figsize=(11, 4.8))
for v, lab, c, ls in [("Rm", "Thị trường (Rm)", "#2b7bba", "-"), ("RF", "Tín phiếu 1 tháng (RF)", "#6c757d", "-"),
                      ("SMB", "SMB (long-short, minh họa)", "#e08a1e", "--"), ("HML", "HML (long-short, minh họa)", "#2e8b57", "--")]:
    ax.plot(capm.index, capm[f"cum_{v}"], label=lab, color=c, ls=ls, lw=1.6)
ax.set_yscale("log"); ax.set_ylabel("Giá trị của 1 USD (thang log)"); ax.legend(loc="upper left")
ax.set_title("Hình 1. Giá trị tích lũy của 1 USD đầu tư từ tháng 7/1926")
plt.tight_layout(); plt.show()

# Hình 2: phân phối bốn chuỗi, đường đứt đỏ là phân phối chuẩn cùng trung bình và độ lệch chuẩn
fig, ax = plt.subplots(2, 2, figsize=(12, 7.5))
for a, v, c in zip(ax.ravel(), vars_, ["#2b7bba", "#e08a1e", "#2e8b57", "#6c757d"]):
    sns.histplot(capm[v], bins=55, stat="density", color=c, ax=a)
    x = np.linspace(capm[v].min(), capm[v].max(), 300)
    a.plot(x, stats.norm.pdf(x, capm[v].mean(), capm[v].std()), "r--", lw=1.5)
    a.set_title(f"{v}  (độ nhọn = {stats.kurtosis(capm[v], fisher=False):.1f}, độ lệch = {stats.skew(capm[v]):.2f})")
    a.set_xlabel("% mỗi tháng")
plt.suptitle("Hình 2. Phân phối các chuỗi lợi suất tháng", y=1.0)
plt.tight_layout(); plt.show()

# Hình 3: Mkt-RF theo thời gian, tô bóng các giai đoạn biến động lớn, kèm biến động trượt 12 tháng
fig, ax = plt.subplots(2, 1, figsize=(12, 7), sharex=True, gridspec_kw={"height_ratios": [2, 1]})
ax[0].plot(capm.index, capm.MktRF, lw=.7, color="#2b7bba")
ax[1].plot(capm.index, capm.vol12_MktRF, lw=1.2, color="#d9534f")
for lab, (s_, e_) in crisis.items():
    for a in ax: a.axvspan(pd.Timestamp(s_), pd.Timestamp(e_), color="gray", alpha=.25)
ax[0].set_ylabel("Mkt-RF (%/tháng)"); ax[1].set_ylabel("Độ lệch chuẩn trượt 12 tháng\n(quy năm, %)")
ax[0].set_title("Hình 3. Lợi suất vượt trội của thị trường và hiện tượng biến động tụ cụm (vùng xám: giai đoạn biến động lớn)")
plt.tight_layout(); plt.show()

# Hình 4: tương quan và lợi suất trung bình theo thập niên
fig, ax = plt.subplots(1, 2, figsize=(13, 4.8))
sns.heatmap(capm[vars_].corr(), annot=True, fmt=".2f", cmap="RdBu_r", center=0, vmin=-1, vmax=1, ax=ax[0])
ax[0].set_title("Ma trận tương quan")
capm.groupby("decade")[["MktRF", "SMB", "HML"]].mean().plot.bar(ax=ax[1], width=.8, color=["#2b7bba", "#e08a1e", "#2e8b57"])
ax[1].axhline(0, color="k", lw=1); ax[1].set_xlabel("Thập niên"); ax[1].set_ylabel("%/tháng")
ax[1].set_title("Lợi suất trung bình theo thập niên")
plt.suptitle("Hình 4. Tương quan và lợi suất trung bình theo thập niên", y=1.02)
plt.tight_layout(); plt.show()

# Hình 5: SMB và HML theo Mkt-RF (mỗi chấm là một tháng)
fig, ax = plt.subplots(1, 2, figsize=(12, 4.8), sharex=True)
for a, v, c in zip(ax, ["SMB", "HML"], ["#e08a1e", "#2e8b57"]):
    a.scatter(capm.MktRF, capm[v], s=8, alpha=.35, color=c)
    for lab, d, col in [("Toàn mẫu", capm, "k"), ("Từ 1963-07", capm.loc["1963-07-01":], "#d9534f")]:
        b1, b0 = np.polyfit(d.MktRF, d[v], 1); xs = np.array([capm.MktRF.min(), capm.MktRF.max()])
        a.plot(xs, b0 + b1 * xs, color=col, lw=2, label=f"{lab}: beta = {b1:.3f}")
    a.axhline(0, color="gray", lw=.6); a.axvline(0, color="gray", lw=.6)
    a.set_xlabel("Mkt-RF (%/tháng)"); a.set_ylabel(f"{v} (%/tháng)"); a.legend(); a.set_title(f"{v} và Mkt-RF")
plt.suptitle("Hình 5. Quan hệ giữa các tài sản kiểm định và lợi suất vượt trội của thị trường", y=1.0)
plt.tight_layout(); plt.show()

# ======== 4.1 Thiết lập 5 mô hình thực nghiệm và bảng tổng hợp
# ---------- Hàm OLS cho chuỗi thời gian: sai số chuẩn thường, HC3 và Newey-West (HAC) ----------
def nw_lag(T):
    return int(np.floor(4 * (T / 100) ** (2 / 9)))          # quy tắc chọn độ trễ thông dụng

def ols_ts(y, X, lag=None):
    y, X = np.asarray(y, float), np.asarray(X, float)
    T, k = X.shape
    XtXi = np.linalg.inv(X.T @ X)
    b = XtXi @ X.T @ y
    e = y - X @ b
    h = np.einsum("ij,jk,ik->i", X, XtXi, X)                   # đòn bẩy
    rss, tss = e @ e, ((y - y.mean()) ** 2).sum()
    s2 = rss / (T - k)
    V_ols = s2 * XtXi
    V_hc3 = XtXi @ (X.T * (e / (1 - h)) ** 2) @ X @ XtXi
    L = nw_lag(T) if lag is None else lag
    Xe = X * e[:, None]
    S = Xe.T @ Xe
    for l in range(1, L + 1):                                   # trọng số Bartlett
        G = Xe[l:].T @ Xe[:-l]
        S += (1 - l / (L + 1)) * (G + G.T)
    V_hac = XtXi @ S @ XtXi
    se = lambda V: np.sqrt(np.diag(V))
    t_hac = b / se(V_hac)
    return dict(b=b, se_ols=se(V_ols), se_hc3=se(V_hc3), se_hac=se(V_hac), V_hac=V_hac,
                t_ols=b / se(V_ols), t_hac=t_hac, p_hac=2 * stats.t.sf(np.abs(t_hac), T - k),
                p_ols=2 * stats.t.sf(np.abs(b / se(V_ols)), T - k),
                T=T, k=k, L=L, rss=rss, tss=tss, r2=1 - rss / tss,
                adj=1 - (rss / tss) * (T - 1) / (T - k), e=e, fit=X @ b, h=h, X=X, yv=y, s2=s2,
                dw=np.sum(np.diff(e) ** 2) / (e @ e))

def fit(df, y, xs, start=None, end=None):
    d = df.loc[start:end] if (start or end) else df
    d = d.dropna(subset=[y] + xs)
    X = np.column_stack([np.ones(len(d))] + [d[v].values for v in xs])
    r = ols_ts(d[y].values, X)
    r.update(names=["alpha"] + xs, dates=d.index, y_name=y)
    return r

# ---------- 5 mô hình ----------
POST = "1963-07-01"
specs = {"M1": ("SMB", ["MktRF"], None), "M2": ("HML", ["MktRF"], None),
         "M3": ("SMB", ["MktRF"], POST), "M4": ("HML", ["MktRF"], POST),
         "M5": ("HML", ["MktRF", "MktRF2"], None)}
models = {k: fit(capm, y, xs, s) for k, (y, xs, s) in specs.items()}

def star(p): return "***" if p < .01 else "**" if p < .05 else "*" if p < .1 else ""
rows = [["Biến phụ thuộc"] + [s[0] for s in specs.values()],
        ["Mẫu"] + ["1926-07 đến 2026-09" if s[2] is None else "1963-07 đến 2026-09" for s in specs.values()]]
for v in ["alpha", "MktRF", "MktRF2"]:
    r1, r2 = [v], [""]
    for k, r in models.items():
        if v in r["names"]:
            i = r["names"].index(v)
            r1.append(f"{r['b'][i]:.4f}{star(r['p_hac'][i])}"); r2.append(f"({r['se_hac'][i]:.4f})")
        else:
            r1.append(""); r2.append("")
    rows += [r1, r2]
rows += [["Số quan sát"] + [str(r["T"]) for r in models.values()],
         ["R2"] + [f"{r['r2']:.3f}" for r in models.values()],
         ["R2 hiệu chỉnh"] + [f"{r['adj']:.3f}" for r in models.values()],
         ["Durbin-Watson"] + [f"{r['dw']:.3f}" for r in models.values()],
         ["Độ trễ Newey-West"] + [str(r["L"]) for r in models.values()]]
print("Alpha tính theo %/tháng. Sai số chuẩn Newey-West (HAC) trong ngoặc.")
print("*** p<0,01  ** p<0,05  * p<0,1\n")
print(pd.DataFrame(rows[1:], columns=rows[0]).to_string(index=False))

# ======== 5.1 Diễn giải alpha, beta và phần bù rủi ro thị trường
print("Diễn giải 4 mô hình CAPM đơn biến (sai số chuẩn Newey-West):")
print(f"{'':4s} {'tài sản':6s} {'alpha %/th':>10s} {'alpha %/năm':>11s} {'t(HAC)':>7s} {'t(OLS)':>7s} {'p(HAC)':>7s} | {'beta':>6s} {'KTC95% (HAC)':>16s} {'R2':>6s}")
for k in ["M1", "M2", "M3", "M4"]:
    r = models[k]; a0, b0 = r["b"]
    lo, hi = b0 - 1.96 * r["se_hac"][1], b0 + 1.96 * r["se_hac"][1]
    print(f"{k:4s} {specs[k][0]:6s} {a0:10.4f} {12*a0:11.2f} {r['t_hac'][0]:7.2f} {r['t_ols'][0]:7.2f} {r['p_hac'][0]:7.4f} | "
          f"{b0:6.3f} [{lo:6.3f}, {hi:6.3f}] {r['r2']:6.3f}")

# Phần bù rủi ro thị trường: hồi quy Mkt-RF lên hằng số
print("\nPhần bù rủi ro thị trường (H0: E[Mkt-RF] = 0):")
for lab, s_ in [("Toàn mẫu 1926-07 đến 2026-09", None), ("Từ 1963-07", POST)]:
    d = capm.loc[s_:] if s_ else capm
    r = ols_ts(d.MktRF.values, np.ones((len(d), 1)))
    print(f"  {lab:30s} trung bình = {r['b'][0]:.3f}%/tháng ({12*r['b'][0]:.1f}%/năm) | t(HAC) = {r['t_hac'][0]:.2f} "
          f"| p = {r['p_hac'][0]:.4f} | Sharpe năm = {r['b'][0]/d.MktRF.std()*np.sqrt(12):.2f}")

# Mô hình M5: kiểm tra phi tuyến theo Treynor-Mazuy
r5 = models["M5"]
print("\nM5 (HML, thêm bình phương Mkt-RF):")
for i, nm in enumerate(r5["names"]):
    print(f"  {nm:7s} b = {r5['b'][i]:9.5f} | SE(HAC) = {r5['se_hac'][i]:8.5f} | t = {r5['t_hac'][i]:6.2f} | p = {r5['p_hac'][i]:.4f}")

# ======== 5.2 Kiểm định đồng thời alpha bằng GRS và đường thị trường chứng khoán (SML)
def grs(df, assets, f="MktRF", start=None):
    """Kiểm định Gibbons-Ross-Shanken: H0 alpha cua moi tai san cung bang 0."""
    d = df.loc[start:] if start else df
    T, N = len(d), len(assets)
    Y, F = d[assets].values, d[[f]].values
    X = np.column_stack([np.ones(T), F])
    B = np.linalg.lstsq(X, Y, rcond=None)[0]
    E = Y - X @ B
    Sig = E.T @ E / T
    alpha = B[0]
    mu = F.mean(0); Om = np.atleast_2d(np.cov(F.T, bias=True))
    sr2 = float(mu @ np.linalg.solve(Om, mu))
    stat = (T - N - 1) / N * (alpha @ np.linalg.solve(Sig, alpha)) / (1 + sr2)
    return stat, stats.f.sf(stat, N, T - N - 1), alpha, T, N

print("Kiểm định GRS với 2 tài sản (SMB, HML), H0: alpha_SMB = alpha_HML = 0")
for lab, s_ in [("Toàn mẫu", None), ("Từ 1963-07", POST)]:
    st, p, al, T, N = grs(capm, ["SMB", "HML"], start=s_)
    print(f"  {lab:11s} T = {T}, N = {N}: GRS F = {st:.3f}, p = {p:.4f} | alpha = {np.round(al, 4)} (%/tháng)")

# Hình 6: SML. Trục hoành là beta, trục tung là lợi suất vượt trội trung bình
prem = capm.MktRF.mean()
fig, ax = plt.subplots(figsize=(8.5, 5.4))
xs = np.array([-0.4, 1.3]); ax.plot(xs, prem * xs, "k-", lw=1.8, label=f"SML lý thuyết: E[R]-Rf = beta x {prem:.2f}%")
pts = [("Tín phiếu (Rf)", 0, 0, "#6c757d"), ("Thị trường", 1, prem, "#2b7bba")]
for lab, b_, m_, c in pts: ax.scatter(b_, m_, s=90, color=c, zorder=3); ax.annotate(lab, (b_, m_), xytext=(6, 6), textcoords="offset points")
for k, c, mk in [("M1", "#e08a1e", "o"), ("M2", "#2e8b57", "o"), ("M3", "#e08a1e", "s"), ("M4", "#2e8b57", "s")]:
    r = models[k]; d = capm.loc[POST:] if specs[k][2] else capm; y = specs[k][0]
    ax.scatter(r["b"][1], d[y].mean(), s=80, color=c, marker=mk, zorder=3)
    ax.plot([r["b"][1]] * 2, [r["b"][1] * d.MktRF.mean(), d[y].mean()], color=c, lw=1.2, ls=":")
    ax.annotate(f"{y} ({'từ 1963' if specs[k][2] else 'toàn mẫu'})", (r["b"][1], d[y].mean()), xytext=(6, -12), textcoords="offset points", fontsize=9)
ax.axhline(0, color="gray", lw=.6); ax.set_xlabel("Beta"); ax.set_ylabel("Lợi suất vượt trội trung bình (%/tháng)")
ax.set_title("Hình 6. Đường SML và vị trí các tài sản (đường chấm: alpha)"); ax.legend(loc="upper left")
plt.tight_layout(); plt.show()

# ======== 6.1 Đa cộng tuyến, phương sai sai số thay đổi, sai dạng hàm, phân phối của phần dư và tự tương quan
# ---- 6.1 Đa cộng tuyến: CAPM đơn biến không có đa cộng tuyến (VIF = 1). Chỉ M5 có Mkt-RF và bình phương ----
r_raw = np.corrcoef(capm.MktRF, capm.MktRF2)[0, 1]
mc = capm.MktRF - capm.MktRF.mean()
r_cen = np.corrcoef(mc, mc ** 2)[0, 1]
print(f"VIF của M5: biến gốc = {1/(1-r_raw**2):.2f} | sau khi tâm hóa = {1/(1-r_cen**2):.2f}")

# ---- 6.2 đến 6.6: bộ kiểm định chẩn đoán ----
def r2_of(y, X):
    e = y - X @ np.linalg.lstsq(X, y, rcond=None)[0]
    return 1 - (e @ e) / ((y - y.mean()) ** 2).sum()

def lb(x, T, L=12):
    x = x - x.mean()
    ac = [(x[l:] @ x[:-l]) / (x @ x) for l in range(1, L + 1)]
    Q = T * (T + 2) * sum(a ** 2 / (T - l) for l, a in enumerate(ac, 1))
    return Q, stats.chi2.sf(Q, L)

def diag(r, L=12):
    e, X, y, T, k = r["e"], r["X"], r["yv"], r["T"], r["k"]
    out = {}
    lm = T * r2_of(e ** 2, X);                    out["Breusch-Pagan (Koenker), chi2"] = (lm, stats.chi2.sf(lm, k - 1))
    f_ = r["fit"]; Xa = np.column_stack([X, f_ ** 2, f_ ** 3]); ea = y - Xa @ np.linalg.lstsq(Xa, y, rcond=None)[0]
    F = ((r["rss"] - ea @ ea) / 2) / ((ea @ ea) / (T - k - 2)); out["Ramsey RESET, F"] = (F, stats.f.sf(F, 2, T - k - 2))
    out["Jarque-Bera"] = tuple(stats.jarque_bera(e))
    out["Durbin-Watson"] = (r["dw"], np.nan)
    lags = np.column_stack([np.r_[np.zeros(l), e[:-l]] for l in range(1, L + 1)])
    lm = T * r2_of(e, np.column_stack([X, lags]));  out["Breusch-Godfrey (12), chi2"] = (lm, stats.chi2.sf(lm, L))
    out["Ljung-Box phần dư (12)"] = lb(e, T)
    out["Ljung-Box phần dư^2 (12)"] = lb(e ** 2, T)
    e2 = e ** 2; Z = np.column_stack([np.ones(T - L)] + [e2[L - l:T - l] for l in range(1, L + 1)])
    lm = (T - L) * r2_of(e2[L:], Z);               out["ARCH-LM (12)"] = (lm, stats.chi2.sf(lm, L))
    return out

dg = {k: diag(models[k]) for k in ["M1", "M2", "M3", "M4"]}
tab = pd.DataFrame({f"{k} ({specs[k][0]}{', từ 1963' if specs[k][2] else ''})":
                    {n: f"{v[0]:9.3f}" + ("" if np.isnan(v[1]) else f"  (p = {v[1]:.4f})") for n, v in d.items()}
                    for k, d in dg.items()})
print("\nKết quả kiểm định chẩn đoán (thống kê và giá trị p):")
pd.set_option("display.width", 250); print(tab.to_string())
print("\nĐộ nhọn của phần dư:", {k: round(float(stats.kurtosis(models[k]["e"], fisher=False)), 2) for k in models})

# ======== 6.2 Điểm ảnh hưởng và đồ thị chẩn đoán
def cook(r):
    return r["e"] ** 2 / (r["k"] * r["s2"]) * r["h"] / (1 - r["h"]) ** 2

print("Quan sát có ảnh hưởng lớn (Cook's D > 4/T) và đòn bẩy (h > 2k/T):")
for k in ["M1", "M2"]:
    r = models[k]; T_, k_ = r["T"], r["k"]; cd = cook(r)
    top = pd.Series(cd, index=r["dates"]).nlargest(5)
    print(f"\n{k} ({specs[k][0]}): Cook > 4/T = {int((cd > 4/T_).sum())} | đòn bẩy > 2k/T = {int((r['h'] > 2*k_/T_).sum())} | Cook lớn nhất = {cd.max():.3f}")
    print("  5 tháng ảnh hưởng nhất:", ", ".join(f"{d:%m/%Y} ({v:.3f})" for d, v in top.items()))

# Hình 7: chẩn đoán phần dư cho mô hình M2 (HML)
r = models["M2"]; e, f_, T_ = r["e"], r["fit"], r["T"]
def acf(x, nlag=36):
    x = x - x.mean(); return np.array([(x[l:] @ x[:-l]) / (x @ x) for l in range(1, nlag + 1)])
fig, ax = plt.subplots(2, 2, figsize=(12, 8.5))
ax[0, 0].scatter(f_, e, s=8, alpha=.4, color="#2e8b57"); ax[0, 0].axhline(0, color="k", lw=1)
ax[0, 0].set(title="Phần dư theo giá trị dự báo", xlabel="Giá trị dự báo", ylabel="Phần dư")
(osm, osr), (sl, ic, _) = stats.probplot(e, dist="norm")
ax[0, 1].scatter(osm, osr, s=8, alpha=.5, color="#2e8b57"); ax[0, 1].plot(osm, sl * osm + ic, "r-")
ax[0, 1].set(title="Q-Q plot phần dư (đuôi dày)", xlabel="Phân vị lý thuyết", ylabel="Phân vị mẫu")
a2 = acf(e ** 2); band = 1.96 / np.sqrt(T_)
ax[1, 0].bar(range(1, 37), a2, color="#d9534f"); ax[1, 0].axhline(band, color="k", ls="--"); ax[1, 0].axhline(-band, color="k", ls="--")
ax[1, 0].set(title="ACF của phần dư bình phương (tụ cụm biến động)", xlabel="Độ trễ (tháng)", ylabel="Tự tương quan")
cd = cook(r); ax[1, 1].vlines(r["dates"], 0, cd, lw=.8, color="#2b7bba"); ax[1, 1].axhline(4 / T_, color="#d9534f", ls="--")
ax[1, 1].set(title="Khoảng cách Cook", xlabel="Thời gian", ylabel="Cook's D")
plt.suptitle("Hình 7. Chẩn đoán phần dư của mô hình M2 (HML theo Mkt-RF)", y=1.0)
plt.tight_layout(); plt.show()

# ======== 7.1 Độ bền vững với các đặc tả và mẫu khác
def spec_rows(asset):
    out = []
    q99 = capm.MktRF.abs().quantile(.99)
    variants = [("Toàn mẫu (CAPM chuẩn)", capm, ["MktRF"], None),
                ("Từ 1963-07", capm, ["MktRF"], POST),
                ("Bỏ các giai đoạn biến động lớn", capm[capm.crisis == 0], ["MktRF"], None),
                ("Bỏ 1% tháng có |Mkt-RF| lớn nhất", capm[capm.MktRF.abs() <= q99], ["MktRF"], None),
                ("Hiệu chỉnh Dimson (thêm Mkt-RF trễ 1 tháng)", capm, ["MktRF", "MktRF_lag1"], None)]
    for lab, d, xs, s_ in variants:
        r = fit(d, asset, xs, s_)
        if len(xs) == 1:
            beta, se_b = r["b"][1], r["se_hac"][1]
        else:                                                   # tổng beta đồng thời và trễ
            w = np.array([0, 1, 1.0]); beta = w @ r["b"]; se_b = np.sqrt(w @ r["V_hac"] @ w)
        out.append([lab, r["T"], r["b"][0], r["t_hac"][0], beta, beta / se_b, r["r2"]])
    return pd.DataFrame(out, columns=["Đặc tả / mẫu", "N", "alpha", "t(alpha)", "beta", "t(beta)", "R2"])

for asset in ["SMB", "HML"]:
    print(f"Tài sản kiểm định: {asset}  (t dùng sai số chuẩn Newey-West)")
    print(spec_rows(asset).round(3).to_string(index=False)); print()

# ======== 7.2 Tính ổn định của beta theo thời gian: các giai đoạn con, kiểm định Chow và beta trượt
# ---- Các giai đoạn con (mỗi giai đoạn khoảng 25 năm) ----
periods = [("1926-07", "1951-06"), ("1951-07", "1976-06"), ("1976-07", "2001-06"), ("2001-07", "2026-09")]
sub = {}
print("Beta theo giai đoạn con (sai số chuẩn Newey-West)")
for asset in ["SMB", "HML"]:
    for s_, e_ in periods:
        r = fit(capm, asset, ["MktRF"], s_ + "-01", e_ + "-28")
        sub[(asset, s_)] = r
        lo, hi = r["b"][1] - 1.96 * r["se_hac"][1], r["b"][1] + 1.96 * r["se_hac"][1]
        print(f"  {asset} {s_} đến {e_}: T = {r['T']:3d} | alpha = {r['b'][0]:7.3f} (t = {r['t_hac'][0]:5.2f}) | beta = {r['b'][1]:6.3f} [{lo:6.3f}, {hi:6.3f}]")

# ---- Kiểm định Chow: hệ số có đổi không? ----
def chow(asset, breaks):
    d = capm.dropna(subset=[asset]); X = np.column_stack([np.ones(len(d)), d.MktRF.values]); y = d[asset].values
    rss_p = ols_ts(y, X)["rss"]
    cuts = [d.index.get_loc(d.loc[b:].index[0]) for b in breaks]
    idx = np.split(np.arange(len(d)), cuts)
    rss_u = sum(ols_ts(y[i], X[i])["rss"] for i in idx); G = len(idx); k = 2
    F = ((rss_p - rss_u) / ((G - 1) * k)) / (rss_u / (len(d) - G * k))
    return F, stats.f.sf(F, (G - 1) * k, len(d) - G * k)

print("\nKiểm định Chow (H0: alpha và beta không đổi giữa các giai đoạn)")
for asset in ["SMB", "HML"]:
    F1, p1 = chow(asset, ["1963-07-01"]); F4, p4 = chow(asset, ["1951-07-01", "1976-07-01", "2001-07-01"])
    print(f"  {asset}: điểm gãy 1963-07  F = {F1:6.2f} (p = {p1:.4f}) | 4 giai đoạn  F = {F4:6.2f} (p = {p4:.4f})")

# ---- Beta trượt 60 tháng ----
def rolling(asset, w=60):
    y, x = capm[asset].values, capm.MktRF.values; res = []
    for t in range(w, len(capm) + 1):
        yy, xx = y[t - w:t], x[t - w:t]; b = np.cov(xx, yy, bias=True)[0, 1] / xx.var()
        a = yy.mean() - b * xx.mean(); e = yy - a - b * xx; se = np.sqrt((e @ e) / (w - 2) / ((xx - xx.mean()) ** 2).sum())
        res.append((capm.index[t - 1], b, se))
    return pd.DataFrame(res, columns=["date", "beta", "se"]).set_index("date")

roll = {a: rolling(a) for a in ["SMB", "HML"]}
for a, d in roll.items():
    print(f"\nBeta trượt 60 tháng của {a}: nhỏ nhất = {d.beta.min():.2f} ({d.beta.idxmin():%m/%Y}), lớn nhất = {d.beta.max():.2f} ({d.beta.idxmax():%m/%Y}), độ lệch chuẩn = {d.beta.std():.2f}")

# Hình 8: beta trượt
fig, ax = plt.subplots(2, 1, figsize=(12, 7), sharex=True)
for a, (nm, d), c in zip(ax, roll.items(), ["#e08a1e", "#2e8b57"]):
    a.plot(d.index, d.beta, color=c, lw=1.6); a.fill_between(d.index, d.beta - 1.96 * d.se, d.beta + 1.96 * d.se, color=c, alpha=.2)
    a.axhline(0, color="k", lw=1); a.set_ylabel(f"Beta của {nm}"); a.set_title(f"Beta trượt 60 tháng của {nm} (dải: KTC 95% theo OLS)")
plt.suptitle("Hình 8. Beta không ổn định theo thời gian", y=1.0)
plt.tight_layout(); plt.show()

# Hình 9: beta theo giai đoạn con
fig, ax = plt.subplots(1, 2, figsize=(12, 4.6), sharey=True)
for a, asset, c in zip(ax, ["SMB", "HML"], ["#e08a1e", "#2e8b57"]):
    bs = [sub[(asset, s_)]["b"][1] for s_, _ in periods]; es = [1.96 * sub[(asset, s_)]["se_hac"][1] for s_, _ in periods]
    a.errorbar([f"{s_[:4]}-{e_[:4]}" for s_, e_ in periods], bs, yerr=es, fmt="o", capsize=5, color=c)
    a.axhline(0, color="k", lw=1); a.set_title(f"Beta của {asset} theo giai đoạn"); a.set_ylabel("Beta (KTC 95%, HAC)")
plt.suptitle("Hình 9. Beta theo bốn giai đoạn con", y=1.02)
plt.tight_layout(); plt.show()

