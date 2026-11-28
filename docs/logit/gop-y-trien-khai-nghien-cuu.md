# Hướng dẫn triển khai đề tài nghiên cứu về mô hình Logit

**Tên đề tài dự kiến**

* Tiếng Anh: *Penalized and Non-Linear Logistic Regression for Imbalanced Employee Attrition: Discrimination, Calibration, and Decision Utility on the IBM HR Dataset*
* Tiếng Việt: *Mô hình hồi quy Logit có điều chuẩn và phi tuyến cho dữ liệu nghỉ việc mất cân bằng: Đánh giá khả năng phân biệt, độ hiệu chuẩn và phân tích đường cong quyết định trên tập dữ liệu IBM HR*

**Mục tiêu:** Hoàn thiện một bản thảo tiếng Anh dài khoảng 4.500--5.500 từ, đủ điều kiện gửi các tạp chí Scopus Q4 thuộc nhóm thống kê ứng dụng, phân tích dữ liệu hoặc hỗ trợ quyết định.

**Cơ sở ban đầu:** Mã nguồn và kết quả khám phá từ báo cáo `logit1.rmd` trên tập dữ liệu IBM HR Analytics ($N = 1.470$ quan sát, trong đó có $237$ nhân viên nghỉ việc, chiếm $16,12\%$).

## 1. Hướng nghiên cứu và lý do chọn đề tài

Bộ dữ liệu IBM HR là dữ liệu giả định, thu thập cắt ngang tại một thời điểm và đã xuất hiện trong rất nhiều bài báo ứng dụng. Nếu viết bài theo hướng quản trị nhân sự (tìm yếu tố khiến nhân viên nghỉ việc rồi đề xuất chính sách cho doanh nghiệp), bản thảo rất dễ bị loại ngay vòng biên tập vì kết quả không áp dụng được cho doanh nghiệp thật.

Thay vào đó, bài báo này đi theo hướng **phương pháp thống kê ứng dụng**: dùng bộ dữ liệu IBM HR làm dữ liệu đối chứng để kiểm tra và khắc phục 4 lỗi kỹ thuật thường gặp khi chạy hồi quy Logit trên dữ liệu mất cân bằng cỡ mẫu trung bình. Nhóm lấy bài báo của Yang & Islam (2021) cùng một số nghiên cứu gần đây trên cùng bộ dữ liệu làm dẫn chứng cụ thể cho các lỗi sau:

1. **Trùng lặp cấu trúc và hiện tượng phân tách bán hoàn toàn:** Đưa cả `Department` lẫn `JobRole` vào cùng một phương trình khiến ma trận thiết kế gần suy biến. Trong Bảng 5 của Yang & Islam (2021), sai số chuẩn của nhóm `Human Resource` tăng vọt lên $S.E. = 10.790,424$ và $\text{Exp}(B)$ vượt $4,4 \times 10^7$. Ngoài ra, phần xử lý dữ liệu của bài báo đó nêu là đã bỏ `EmployeeNumber`, `DailyRate`, `HourlyRate`, `MonthlyRate`, nhưng các biến này vẫn còn nguyên trong bảng kết quả hồi quy.
2. **Đa cộng tuyến ở nhóm biến thâm niên và các nhóm có ít quan sát:** Bộ dữ liệu có tương quan rất cao giữa `MonthlyIncome` và `JobLevel` ($r = 0,95$), `MonthlyIncome` và `TotalWorkingYears` ($r = 0,77$), `YearsAtCompany` với `YearsWithCurrManager` ($r = 0,77$) và `YearsInCurrentRole` ($r = 0,76$). Khi đưa hết các biến này vào ước lượng hợp lý cực đại (MLE) thông thường, hệ số của `YearsAtCompany` đảo sang dấu dương ($B = 0,098$, $p < 0,05$ trong Yang & Islam, 2021), trái với giả thuyết ban đầu về sự gắn bó. Thêm vào đó, một số nhóm trong `JobRole` có dưới $5$ ca nghỉ việc, làm ước lượng MLE dễ lệch.
3. **Mặc định quan hệ tuyến tính và đánh giá trên một lần chia mẫu duy nhất:** Phần lớn bài trước dùng dạng tuyến tính thuần túy trên thang logit và chỉ chia tập huấn luyện/kiểm tra một lần theo tỷ lệ 80/20. Với $1.470$ dòng, tập kiểm tra $20\%$ chỉ có khoảng $47$ ca nghỉ việc, nên kết quả đánh giá phụ thuộc mạnh vào cách chia ngẫu nhiên.
4. **Dựa vào `accuracy` và bỏ qua chi phí sai sót:** Các nghiên cứu trước hay so sánh mô hình qua độ chính xác phân loại ($84,56\%$ đến $88,43\%$) mà không kiểm tra độ hiệu chuẩn xác suất. Với tỷ lệ nghỉ việc $16,12\%$, quy tắc đơn giản "luôn đoán không nghỉ việc" đã đạt `accuracy` $83,88\%$. Cả ngưỡng cắt $0,5$ lẫn ngưỡng Youden $J$ (đang dùng ở `logit1.rmd`) đều coi chi phí bỏ sót người sắp nghỉ việc và chi phí can thiệp nhầm bằng nhau, nên chưa gắn với bài toán ra quyết định thực tế.

## 2. Phần giữ lại từ `logit1.rmd` và phần làm thêm

Nhóm giữ nguyên các quy tắc làm sạch và kiểm tra chặt chẽ đã có trong `logit1.rmd`, sau đó mở rộng ở 4 điểm chính:

| Nội dung | Đang có trong `logit1.rmd` | Phần làm thêm cho bản thảo Q4 |
| --- | --- | --- |
| Biến đầu vào | Giữ 13 biến; bỏ 4 biến hằng/ID; bỏ `Department`, giữ `JobRole`; cố định nhóm tham chiếu. | Thêm 7 biến hành vi và đãi ngộ từ bộ gốc; kiểm tra lại GVIF và loại `JobLevel` do trùng thông tin với `MonthlyIncome`. |
| Các mô hình Logit | So sánh 2 mô hình: MLE tuyến tính và MLE dùng `ns(df = 2)`. | So sánh 4 mô hình: M1 (MLE tuyến tính), M2 (Natural Spline MLE), M3 (Firth Logit), M4 (Ridge và Elastic-Net Spline Logit). |
| Cách đánh giá ngoài mẫu | Chia 80/20 một lần, kết hợp 5-fold CV trong tập huấn luyện. | Chuyển sang Repeated Nested Cross-Validation ($10$ lần lặp $\times$ $5$-fold ngoài; $5$-fold trong để chọn siêu tham số cho M4). |
| Thước đo | ROC-AUC, AP, Brier, Log-loss, calibration intercept/slope, ngưỡng Youden $J$. | Tính thêm chỉ số hiệu chuẩn tích hợp ICI (dùng LOESS) và chạy Decision Curve Analysis (tính Net Benefit theo dải ngưỡng xác suất). |

## 3. Yêu cầu kỹ thuật trên R

Mã nguồn chia làm hai phần chạy độc lập nhau giống cách tổ chức của `logit1.rmd`: **Phần A (Suy luận trên toàn mẫu)** và **Phần B (Dự đoán ngoài mẫu)**. Không lấy p-value từ Phần A để lọc biến rồi đưa sang Phần B.

### 3.1. Các gói R cần dùng và danh sách biến

Nhóm ghi lại đầy đủ phiên bản R và các gói đã dùng bằng `sessionInfo()`:

* Xử lý dữ liệu và vẽ đồ thị: `dplyr`, `tidyr`, `ggplot2`, `scales`, `patchwork`
* Ước lượng và chẩn đoán mô hình: `splines`, `car`, `brglm2`, `glmnet`
* Chia mẫu và đánh giá: `rsample`, `pROC`, `dcurves` (hoặc tự viết hàm tính Net Benefit để chủ động kiểm tra công thức)

Danh sách biến sử dụng trong mô hình mở rộng:

* 13 biến giữ lại từ `logit1.rmd`: `Age`, `DistanceFromHome`, `MonthlyIncome`, `TotalWorkingYears`, `YearsAtCompany`, `YearsInCurrentRole`, `YearsWithCurrManager`, `Gender`, `MaritalStatus`, `OverTime`, `JobRole`, `JobSatisfaction`, `EnvironmentSatisfaction`.
* 7 biến lấy thêm từ bộ dữ liệu gốc: `BusinessTravel`, `NumCompaniesWorked`, `YearsSinceLastPromotion`, `WorkLifeBalance`, `JobInvolvement`, `StockOptionLevel`, `TrainingTimesLastYear`.
* Các biến không đưa vào mô hình chính (có kèm bảng chéo hoặc GVIF để giải thích): `Department` (chồng lấp với `JobRole`), `JobLevel` (tương quan $0,95$ với `MonthlyIncome`), `DailyRate`, `HourlyRate`, `MonthlyRate` cùng 4 biến `EmployeeNumber`, `EmployeeCount`, `Over18`, `StandardHours`.

Sau khi chốt danh sách biến, nhóm tính số biến cố trên mỗi bậc tự do ($EPV$). Với $237$ ca nghỉ việc và khoảng $35$--$45$ tham số (tính cả biến giả và spline), $EPV$ chỉ khoảng $5$--$7$. Con số này nhỏ hơn ngưỡng kinh nghiệm $10$, là lý do trực tiếp để thử nghiệm Firth Logit và Ridge/Elastic-Net thay vì chỉ dùng MLE.

### 3.2. Phần A: Suy luận trên toàn mẫu

1. **Ước lượng 3 mô hình M1, M2, M3:**
   * M1 dùng `glm(..., family = binomial("logit"))` với các biến liên tục ở dạng tuyến tính.
   * M2 thay các biến liên tục bằng `splines::ns(x, df = 2)` (kiểm tra thêm trường hợp `df = 3` nếu mô hình vẫn hội tụ bình thường). Chạy kiểm định tỷ số hợp lý (LRT) chung giữa M1 và M2, kèm kiểm định riêng từng biến có hiệu chỉnh Holm như trong `logit1.rmd`.
   * M3 dùng phương pháp giảm thiên lệch của Firth qua `glm(..., family = binomial("logit"), method = brglm2::brglmFit, type = "AS_mean")` cho cả bản tuyến tính và bản spline. Đối chiếu trực tiếp sai số chuẩn và độ rộng khoảng tin cậy $95\%$ ở những nhóm `JobRole` ít quan sát giữa M1/M2 và M3.
2. **Tính tương phản chuẩn hóa:**
   * Không lấy $\exp(\hat{\beta})$ của từng thành phần cơ sở trong spline để đọc thành Odds Ratio (OR).
   * Dùng lại hàm `compute_standardized_contrast` trong `logit1.rmd` để tính OR và chênh lệch xác suất trung bình $\Delta P$ khi một biến liên tục tăng từ phân vị $25\%$ lên phân vị $75\%$ (và so sánh mức cao nhất với mức tham chiếu cho biến phân loại). Tính sai số chuẩn bằng delta method và hiệu chỉnh Holm cho họ các giả thuyết chính.
3. **Kiểm tra hiện tượng đổi dấu của `YearsAtCompany`:**
   * Chạy thêm hai mô hình lồng nhau: mô hình chỉ có `YearsAtCompany` (bỏ `YearsInCurrentRole`, `YearsWithCurrManager`, `YearsSinceLastPromotion`) và mô hình có đủ cả 4 biến thâm niên.
   * Lập bảng đối chiếu hệ số, $S.E.$, GVIF và $\Delta P$ của `YearsAtCompany` giữa hai mô hình. Phần giải thích cần nêu rõ ý nghĩa thống kê: khi giữ cố định số năm ở vị trí hiện tại và số năm từ lần thăng chức gần nhất, biến `YearsAtCompany` không còn phản ánh thâm niên chung mà phản ánh phần thời gian còn lại trước đó.
4. **Kiểm định tương tác đã chọn trước:**
   * Chỉ kiểm tra tối đa 2 cặp tương tác có ý nghĩa thực tế rõ ràng: `OverTime` $\times$ `WorkLifeBalance` và `YearsAtCompany` $\times$ `YearsSinceLastPromotion`.
   * Dùng kiểm định LRT có hiệu chỉnh Holm. Nếu không có ý nghĩa thống kê thì ghi nhận kết quả và không đưa vào mô hình chính.

### 3.3. Phần B: Đánh giá dự đoán ngoài mẫu bằng Repeated Nested CV

1. **Thiết kế vòng lặp kiểm chứng:**
   * Cố định `set.seed(20261108)`.
   * Vòng ngoài gồm $10$ lần lặp $\times$ $5$-fold phân tầng theo `Attrition` (tạo ra $50$ tập kiểm tra ngoài).
   * Vòng trong chạy $5$-fold phân tầng ngay trong phần dữ liệu huấn luyện của từng fold ngoài để chọn siêu tham số cho M4: duyệt lưới $\alpha \in \{0; 0,25; 0,5; 0,75; 1\}$ và tìm $\lambda$ làm nhỏ nhất log-loss ngoài fold.
   * Tất cả bước tính knot của `splines::ns()`, chuẩn hóa biến đầu vào cho `glmnet` và kiểm tra mức factor chưa xuất hiện (`guard_unseen_levels`) phải nằm hoàn toàn bên trong phần huấn luyện của từng fold, không để thông tin từ fold kiểm tra lọt sang.
2. **Các mô hình cần so sánh trên 50 fold ngoài:**
   * M1: Standard MLE tuyến tính.
   * M2: Natural Spline MLE (`df = 2`).
   * M3: Firth Logit (chạy cả bản tuyến tính và bản spline).
   * M4: Penalized Spline Logit qua `glmnet` (tách riêng kết quả Ridge $\alpha = 0$ và Elastic-Net có $\alpha$ chọn từ vòng trong).
   * Mô hình cơ sở (Baseline): gán mọi quan sát trong fold kiểm tra một xác suất bằng đúng tỷ lệ nghỉ việc của fold huấn luyện tương ứng.
3. **Các nhóm thước đo cần báo cáo:**
   * **Khả năng phân biệt:** ROC-AUC và Average Precision (AP). Báo cáo trung bình, độ lệch chuẩn (hoặc trung vị và IQR) trên 50 fold. Khi so sánh hai mô hình theo cặp trên cùng 50 fold, dùng kiểm định $t$ đã hiệu chỉnh tương quan mẫu lặp (Nadeau--Bengio) hoặc báo cáo trực tiếp phân phối hiệu số giữa hai mô hình theo từng fold.
   * **Độ hiệu chuẩn xác suất:** Brier score, Log-loss, Calibration Intercept, Calibration Slope và chỉ số ICI (trung bình trị tuyệt đối chênh lệch giữa xác suất dự đoán và đường cong thực nghiệm ước lượng bằng LOESS trên các dự đoán ngoài fold). Gộp dự đoán ngoài fold theo từng lần lặp để vẽ đồ thị hiệu chuẩn trung bình kèm dải biến thiên.
   * **Phân tích đường cong quyết định (Decision Curve Analysis - DCA):** Tính lợi ích ròng (Net Benefit) trên dải ngưỡng xác suất $p_t \in [0,05; 0,50]$ với bước nhảy $0,01$:
     $$
     NB(p_t) = \frac{TP(p_t)}{N} - \frac{FP(p_t)}{N} \left( \frac{p_t}{1 - p_t} \right)
     $$
     Tỷ số $\frac{p_t}{1 - p_t}$ biểu diễn trọng số chi phí giữa một ca can thiệp nhầm và một ca dự đoán đúng người sắp nghỉ việc. Vẽ đường DCA của M1--M4 cùng hai đường chuẩn là "Can thiệp tất cả" (*Treat All*) và "Không can thiệp ai" (*Treat None*), từ đó chỉ rõ khoảng ngưỡng $p_t$ mà các mô hình Logit có điều chuẩn cho Net Benefit tốt hơn hai đường chuẩn và tốt hơn MLE thường.

## 4. Bố cục bài báo tiếng Anh và bảng hình cần xuất

Bản thảo chia làm 6 mục, tuân thủ các yêu cầu báo cáo cơ bản cho mô hình dự đoán (tham khảo bảng kiểm TRIPOD):

1. **Abstract (200--250 từ):** Nêu vấn đề kỹ thuật trên bộ IBM HR, tóm tắt 4 mô hình Logit, thiết kế $10 \times 5$ Repeated Nested CV và DCA, kèm các con số kết quả chính (ROC-AUC, AP, calibration slope, ICI và khoảng ngưỡng $p_t$ có Net Benefit dương).
2. **Introduction (600--800 từ):** Điểm lại ngắn gọn 3--4 bài báo gần đây dùng tập IBM HR (nêu cụ thể lỗi ở Yang & Islam, 2021), chỉ ra khoảng trống về mặt đánh giá mô hình Logit trên dữ liệu mất cân bằng, rồi đặt 3 câu hỏi nghiên cứu rõ ràng.
3. **Data and Methodology (1.200--1.500 từ):** Mô tả dữ liệu, lý do lọc biến qua GVIF, viết công thức toán học ngắn gọn của 4 mô hình, cách tính tương phản chuẩn hóa, quy trình Repeated Nested CV và công thức của các thước đo hiệu chuẩn, DCA.
4. **Results (1.200--1.500 từ):** Trình bày riêng kết quả Phần A (suy luận, độ nhạy `YearsAtCompany`, so sánh sai số chuẩn MLE và Firth) và kết quả Phần B (hiệu năng trên 50 fold, đồ thị hiệu chuẩn, đường cong DCA).
5. **Discussion and Limitations (800--1.000 từ):** Giải thích vì sao Firth hoặc Ridge giúp calibration slope tiến gần $1$ hơn so với MLE khi $EPV$ thấp; so sánh thẳng với các bài chỉ báo cáo `accuracy`; liệt kê đầy đủ hạn chế (dữ liệu giả định, dữ liệu cắt ngang, không suy ra nhân quả, rủi ro thiên lệch nếu dùng `Gender`, `Age`, `MaritalStatus` để chấm điểm nhân sự ngoài thực tế).
6. **Conclusion (200--300 từ):** Tóm tắt 3 điểm lưu ý thực hành khi dùng mô hình Logit cho dữ liệu mất cân bằng cỡ mẫu nhỏ và trung bình.

Danh sách bảng và hình cần chuẩn bị (đồ thị xuất độ phân giải 300 dpi):

* **Bảng 1:** Thống kê mô tả, số lượng nhóm có dưới $5$ ca nghỉ việc và giá trị GVIF trước/sau khi bỏ `Department` và `JobLevel`.
* **Bảng 2:** Kết quả tương phản chuẩn hóa (OR, $\Delta P$, khoảng tin cậy $95\%$, $p$-Holm) của M1, M2 và M3.
* **Bảng 3:** So sánh hệ số, $S.E.$, GVIF và $\Delta P$ của `YearsAtCompany` trước và sau khi đưa thêm 3 biến thâm niên còn lại vào mô hình.
* **Bảng 4:** Kết quả đánh giá ngoài mẫu trên $10 \times 5$ Repeated Nested CV (ROC-AUC, AP, Brier, Log-loss, Calibration Intercept, Calibration Slope, ICI) của M1--M4 và Baseline.
* **Hình 1:** Đồ thị xác suất điều chỉnh phi tuyến (có vạch rug biểu thị mật độ dữ liệu) cho các biến liên tục có dấu hiệu phi tuyến hoặc liên hệ mạnh.
* **Hình 2:** Biểu đồ so sánh sai số chuẩn và độ rộng khoảng tin cậy $95\%$ giữa Standard MLE và Firth Logit ở các nhóm `JobRole` ít quan sát.
* **Hình 3:** Đồ thị ROC, Precision--Recall và đồ thị hiệu chuẩn LOESS tổng hợp từ Repeated Nested CV.
* **Hình 4:** Đồ thị Decision Curve Analysis so sánh Net Benefit của M1--M4 với *Treat All* và *Treat None* trên đoạn $p_t \in [0,05; 0,50]$.

## 5. Chia việc và tiến độ 6 tuần

Nhóm nên gồm 3 hoặc 4 sinh viên, phân công theo từng phần việc cụ thể:

* **Thành viên 1 (Dữ liệu và Phần A):** Lập bảng kiểm tra bộ biến mở rộng, chạy GVIF, ước lượng M1--M3 (`glm`, `splines`, `brglm2`), tính tương phản chuẩn hóa, chạy kiểm tra đổi dấu `YearsAtCompany` và kiểm định 2 cặp tương tác.
* **Thành viên 2 (Phần B - Nested CV và DCA):** Viết mã chạy $10 \times 5$ Repeated Nested CV cho M1--M4 (`glmnet`, `brglm2`), kiểm tra không để rò rỉ dữ liệu giữa các fold, tính các chỉ số hiệu chuẩn (ICI, intercept, slope) và vẽ các Hình 3, Hình 4.
* **Thành viên 3 (Tổng quan tài liệu và bản thảo tiếng Anh):** Đọc các bài báo giai đoạn 2020--2026 dùng tập IBM HR để tổng hợp các lỗi kỹ thuật thường gặp; ghép kết quả từ Thành viên 1 và 2 để viết bản thảo tiếng Anh, chuẩn hóa trích dẫn và bảng số liệu.
* **Thành viên 4 (Nếu nhóm có 4 người - Chạy kiểm chứng độc lập):** Chạy lại toàn bộ mã R từ đầu trên máy khác để bảo đảm tái lập được đúng kết quả, kiểm tra chéo toàn bộ con số giữa văn bản và bảng/hình, rà soát các lỗi diễn giải thống kê.

Tiến độ dự kiến theo từng tuần:

* **Tuần 1:** Chốt danh sách biến, chạy kiểm tra đa cộng tuyến và ô thưa, chạy thử `brglm2` và `glmnet`. Hoàn thành bảng tổng hợp các bài báo trước đó dùng tập IBM HR.
* **Tuần 2:** Xong toàn bộ mã R và kết quả Phần A (M1--M3, tương phản Q25 $\rightarrow$ Q75, phân tích `YearsAtCompany`). Nộp giảng viên xem trước kết quả Phần A.
* **Tuần 3:** Hoàn thành mã nguồn $10 \times 5$ Repeated Nested CV cho Phần B; kiểm tra toàn bộ 50 fold hội tụ bình thường và không phát sinh cảnh báo ẩn.
* **Tuần 4:** Tính xong ICI, vẽ xong đồ thị hiệu chuẩn và Decision Curve Analysis (Bảng 4, Hình 3, Hình 4). Khóa toàn bộ số liệu.
* **Tuần 5:** Hoàn thiện bản thảo tiếng Anh đủ 6 mục, đối chiếu lại 100% số liệu trong bài với đầu ra từ R.
* **Tuần 6:** Rà soát câu chữ tiếng Anh cho tự nhiên, sửa lỗi định dạng theo mẫu của tạp chí dự kiến, đóng gói mã R và file hướng dẫn chạy lại để nộp kèm bản thảo.

## 6. Lưu ý về diễn giải thống kê, cách viết và tạp chí dự kiến

### 6.1. Các lỗi thống kê cần tránh

* Không viết theo nghĩa nhân quả (*causes*, *leads to*, *reduces attrition*) vì đây là dữ liệu quan sát cắt ngang và là dữ liệu giả định; chỉ dùng các cách diễn đạt liên hệ có điều kiện (*is associated with*, *adjusted odds ratio*, *standardized probability difference*).
* Không kết luận biến "không có ảnh hưởng" hay "chấp nhận $H_0$" khi $p \ge 0,05$.
* Không xóa các dòng có Cook's distance $> 4/n$ ra khỏi mô hình chính; chỉ giữ ở phần phân tích độ nhạy phụ.
* Không mũ hóa từng hệ số cơ sở của spline thành OR.
* Không lấy `accuracy` làm tiêu chí chính để xếp hạng mô hình.

### 6.2. Yêu cầu về cách viết bản thảo tiếng Anh

Nhiều tạp chí hiện kiểm tra rất kỹ bài viết có dấu hiệu tạo tự động bằng AI. Khi soạn thảo, nhóm cần lưu ý:

* Bỏ các cụm mở đầu sáo rỗng và tính từ phóng đại như *In today's rapidly evolving landscape*, *plays a pivotal/crucial role*, *delve into*, *underscore the importance*, *comprehensive framework*, *groundbreaking*, *seamlessly*, *shed light on*, *it is worth noting that*, *a testament to*.
* Không mở đầu các đoạn liên tiếp bằng cùng một khuôn (*Moreover*, *Furthermore*, *Additionally*, *In conclusion*) và không lạm dụng gạch đầu dòng có cụm từ in đậm ở đầu câu.
* Nêu thẳng chủ ngữ và con số thay vì nhận xét chung chung. Chẳng hạn, thay vì viết *"Ridge regularization substantially improves model stability and delivers robust performance"*, hãy viết *"Ridge spline logit ($\alpha = 0$) moved the mean calibration slope from 0.84 to 0.99 and reduced mean log-loss by 0.014 across the 50 outer test folds"*.
* Ghi nhận trung thực những chỗ mô hình mở rộng không vượt trội hơn mô hình đơn giản (ví dụ ROC-AUC giữa M1 và M4 gần như ngang nhau, khác biệt chủ yếu nằm ở độ hiệu chuẩn và Net Benefit ở dải ngưỡng thấp).

### 6.3. Một số tạp chí Scopus Q4 nên xem trước

Trong tuần 2, nhóm kiểm tra trước phạm vi nhận bài (*Aims & Scope*), phí xuất bản và thời gian phản biện của các tạp chí sau để chọn nơi nộp phù hợp:

* Nhóm thống kê ứng dụng và phân tích dữ liệu: *Statistics, Optimization & Information Computing*, *Communications in Statistics: Case Studies, Data Analysis and Applications*, *Journal of Statistical Computation and Simulation* (dao động Q3--Q4 tùy năm), *Data* (MDPI, có phí xuất bản), *Analytics* (MDPI).
* Nhóm phân tích dữ liệu và hệ thống hỗ trợ quyết định: *International Journal of Data Analysis Techniques and Strategies*, *International Journal of Business Analytics*, *Journal of Applied Data Sciences*.