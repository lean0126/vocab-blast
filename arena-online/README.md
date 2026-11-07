# VOCAB BLAST ARENA ONLINE — cô LÊ THỊ NGỌC TRINH

Phiên bản 3.0 gồm game offline cũ (index.html) và hệ thống multiplayer online mới (online.html). **Không có dữ liệu online giả lập.** Chức năng online chỉ chạy sau khi bạn tự cấu hình Supabase.

## Bắt đầu từ GitHub Pages hiện có

1. Sao lưu bản cũ bằng cách tải ZIP của repository.
2. Tạo project tại https://supabase.com/dashboard (chọn khu vực gần Việt Nam).
3. Trong Supabase **SQL Editor**, dán toàn bộ nội dung `schema.sql`, nhấn Run. Chỉ chạy script khởi tạo **một lần** trên project mới, vì các INSERT dữ liệu mẫu sẽ bị lặp nếu chạy lại.
4. Trong SQL Editor chạy lệnh sau, **thay mã lớp bằng mã bí mật riêng**:

```sql
insert into public.classes(name,code_hash)
values ('Lớp tiếng Anh cô Trinh', crypt('MA_LOP_BI_MAT_2026',gen_salt('bf')));
```

Nếu lệnh báo không tìm thấy `crypt`, dùng `extensions.crypt` và `extensions.gen_salt`.

5. Vào **Authentication → Providers / Sign In**, bật **Anonymous Sign-ins**. Điều này cần thiết để học sinh chỉ nhập tên + mã lớp. Kiểm tra email/password provider cũng đang bật cho giáo viên.
6. Trong **Project Settings → API / Data API**, lấy **Project URL** và **anon key/publishable key**. Dán vào `config.js`. **Tuyệt đối không dùng service_role hoặc secret key trong website.**
7. Đăng ký một tài khoản email/password dành cho giáo viên trong **Authentication → Users** của Supabase (có thể dùng nút Add user; chọn mật khẩu mạnh). Dùng nút "Đăng nhập giáo viên" ở `online.html`, sau đó nhập tên + mã lớp để tạo hồ sơ.
8. Trong **Authentication → Users**, sao chép UUID của tài khoản giáo viên. Trong SQL Editor chạy:

```sql
update public.profiles set role='teacher'
where id='UUID_CUA_GIAO_VIEN';
```

9. Giải nén ZIP, mở thư mục `arcade-vocab`. Tải **các file bên trong** lên GitHub repository `lean0126/vocab-blast` trong thư mục `arcade-vocab`, xác nhận thay thế file cũ bằng Commit changes. `schema.sql` có thể để trong repository vì không chứa mã lớp bí mật thật hay mật khẩu; tuy nhiên không được lưu bí mật trong SQL đã commit.
10. Chờ GitHub Pages hoàn tất. Mở `https://lean0126.github.io/vocab-blast/arcade-vocab/online.html` trên 2 thiết bị. Nhập 2 tên khác nhau cùng mã lớp. Một máy tạo phòng, máy kia nhập mã phòng. Chủ phòng nhấn bắt đầu.

## Luồng thi đấu

- Phòng SOLO tối đa 2 người; phòng nhóm tối đa 30 người.
- Chủ phòng chờ đủ ít nhất 2 người và bắt đầu. Máy chủ chọn ngẫu nhiên 10 câu chung; mỗi câu 21 giây. Điểm đúng tính theo tốc độ, sai 0 điểm. Máy chủ lưu câu trả lời tối đa một lần/câu/người.
- Kết thúc sau 210 giây; mỗi người được XP và xu, người dẫn đầu có thêm trận thắng. Quyết toán chỉ thực hiện một lần (trường `settled`).
- TOP lớp sắp theo XP, thắng trận; xu dùng gửi yêu cầu đổi quà; giáo viên duyệt hoặc từ chối, từ chối hoàn xu.
- Người chơi mới được định danh bằng Supabase Anonymous Auth. Dữ liệu tồn tại trong Supabase, nhưng **nếu xóa dữ liệu trình duyệt hoặc đổi thiết bị, học sinh không tự khôi phục được danh tính cũ**. Để có tài khoản bền vững qua nhiều thiết bị cần nâng cấp sang email/OTP hoặc mã học sinh do giáo viên cấp với quy trình xác thực.

## Giới hạn quan trọng trước khi dùng thi đua nhận quà thật

- Bản này dùng polling ~1.8 giây (đồng bộ qua máy chủ, không giả lập). Không dùng WebSocket; trạng thái có thể trễ vài giây.
- Mã lớp chỉ giới hạn người biết mã; không chứng minh danh tính. Học sinh có thể tạo nhiều danh tính trên trình duyệt khác, nhờ bạn trả lời hộ, hoặc tổ chức trận để tích điểm. **Chưa đủ chống gian lận cho phần thưởng có giá trị**. Giáo viên nên kiểm tra người nhận và kết quả trước khi phát quà. Để triển khai thi đấu có thưởng nghiêm túc, cần xác thực tài khoản thật, giới hạn số trận thưởng/ngày, chống bot và quản trị/kiểm toán sâu hơn.
- Bảng xếp hạng hiển thị tên đã nhập, không nên dùng thông tin nhạy cảm của học sinh.
- Giáo viên cần quản lý mã lớp riêng; đổi mã lớp bằng cách cập nhật `code_hash` trong Supabase SQL Editor nếu bị lộ.
- Học sinh cần có Internet. GitHub Pages miễn phí chỉ host tĩnh; Supabase có giới hạn miễn phí và có thể tạm dừng project không hoạt động theo chính sách của nhà cung cấp.
- Bản đầu tiên này chưa được kiểm thử end-to-end với project Supabase thực do chưa có thông tin project; cần kiểm thử 2 thiết bị trước khi sử dụng chính thức.

## File

- `index.html`, `app.js`, `style.css`, `words.js`: 6 trò luyện tập cũ.
- `online.html`, `online.css`, `online.js`: sảnh, phòng SOLO, phòng nhóm, TOP, đổi quà, trang giáo viên.
- `config.js`: nơi cấu hình URL và publishable/anon key Supabase.
- `schema.sql`: bảng, RLS, hàm RPC chấm điểm, tạo phòng, ví xu và duyệt quà.

## Mở rộng

Thêm câu hỏi bằng `insert into public.questions(vi,en,distractors) values ('Cây xanh','Tree',array['Flower','River','House']);` (cần đủ 3 đáp án nhiễu). Thêm quà bằng `insert into public.rewards(title,cost) values ('Quà mới',500);`. Không bao giờ cấp quyền ghi trực tiếp cho `anon` vào bảng điểm hoặc ví xu.
