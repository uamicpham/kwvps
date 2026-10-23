# KwVPS 0.50.9 — sửa bước chuẩn bị thư mục Laravel

- Sửa lỗi tạo `deploy/shared/storage/app/public` báo quyền không đúng dù `chmod` trả thành công. KwVPS vẫn chạy thao tác dưới UID riêng của site, nhưng đặt group `www-data` cho đúng lệnh `chmod 2750`; Linux sẽ giữ bit setgid và thư mục upload con kế thừa group này. Không thêm site user vào nhóm `www-data` toàn hệ thống.
- Thêm kiểm thử mô phỏng Linux tự bỏ bit setgid khi user không thuộc group đích. Các thư mục `source/` và `deploy/` còn tồn tại sẽ không bị ghi đè; nếu lần chuẩn bị trước không dọn hết thư mục rỗng, hãy kiểm tra thủ công trước khi chạy lại.

Không tự cập nhật VPS. Với VPS có website thật, hãy sao lưu/snapshot và kiểm tra trạng thái site trước khi chọn cập nhật KwVPS từ menu. Laravel vẫn chưa được kiểm thử đầu-cuối trên VPS production; backup source hiện chỉ gồm `public/`, không gồm `.env`, release, storage hay DB Laravel.
