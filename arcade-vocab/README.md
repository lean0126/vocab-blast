# VOCAB BLAST – Game từ vựng THCS

## Chạy game
1. Giải nén file ZIP.
2. Mở `index.html` bằng Chrome, Edge, Safari hoặc Firefox.
3. Chọn 1 trong 6 chế độ, chọn cấp độ rồi chơi.

## 6 chế độ
- Săn từ: chọn đáp án tiếng Anh bay xung quanh nghĩa tiếng Việt.
- Ghép cặp: ghép 5 cặp từ Anh – Việt.
- Điền chữ: hoàn thiện chữ cái bị thiếu.
- Nghe từ: nghe giọng đọc trình duyệt và chọn nghĩa.
- 60 giây: thử thách trả lời liên tục trong 60 giây.
- Nhìn hình: đoán từ qua emoji.

## Chia sẻ cho người khác bằng đường link (miễn phí)
**Cách đơn giản: Netlify Drop**
1. Truy cập https://app.netlify.com/drop
2. Kéo thả **cả thư mục `arcade-vocab`** (chứa index.html, style.css, app.js, words.js) vào trang.
3. Netlify cung cấp URL `https://...netlify.app`. Sao chép URL gửi học sinh. Nếu trang yêu cầu đăng nhập, tạo tài khoản miễn phí.
4. Khi cập nhật game, triển khai lại phiên bản mới trong Netlify.

**Cách khác: GitHub Pages**
1. Tạo repository GitHub, tải 4 file lên thư mục gốc.
2. Vào Settings > Pages > Build and deployment > Deploy from a branch, chọn `main` và `/ (root)`.
3. Chờ triển khai và chia sẻ link Pages.

## Chỉnh sửa, bổ sung từ
Mở `words.js`. Mỗi từ được viết dưới dạng `['english','nghĩa tiếng Việt','emoji']`.
Thêm một mục mới trước dấu `]` cuối danh sách, ví dụ `['volcano','núi lửa','🌋'],`.
Dữ liệu được phân cấp dựa theo **vị trí** trong danh sách: 100 từ đầu thuộc Dễ, tiếp theo đến 155 thuộc Trung bình, còn lại thuộc Khó. Cấp độ Trung bình và Khó bao gồm cả từ của cấp trước.

## Thêm chế độ chơi mới
- Thêm một phần tử vào mảng `modes` trong `app.js`.
- Tạo hàm render chế độ mới và nối vào `render()`.
- Tận dụng `correct()`, `incorrect()`, `next()` và `finish()` để tính điểm.

## Ghi chú
- Không cần backend; không thu thập dữ liệu học sinh. Điểm cao nhất lưu trong localStorage của **từng trình duyệt/thiết bị**.
- Chế độ nghe cần trình duyệt hỗ trợ Web Speech API và giọng tiếng Anh. Nếu trình duyệt không có giọng, nên dùng Chrome/Edge với giọng nói đã cài.
- Google Fonts cần mạng; nếu offline, game tự dùng font hệ thống.
- Hình ở chế độ 6 dùng emoji, hiển thị có thể khác nhau giữa các thiết bị.
- Dùng website HTTPS để chia sẻ; không có chức năng bảng xếp hạng toàn lớp hoặc tài khoản trực tuyến trong bản này.
