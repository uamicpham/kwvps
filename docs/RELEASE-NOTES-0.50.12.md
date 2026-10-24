# KwVPS 0.50.12 — Cải thiện kiểm tra và thông báo lỗi Cloudflare Real IP

- Menu **Bảo mật/Cloudflare → Cập nhật Cloudflare Real IP** kiểm tra quyền root ngay khi mở menu tương tác; thông báo rõ lệnh `sudo kwvps` nếu chạy bằng tài khoản thường thay vì lỗi im lặng.
- Bổ sung thông báo lỗi chi tiết cho từng điều kiện tiền kiểm tra: hệ điều hành Ubuntu 24.04, định danh cài đặt `install-id`, công cụ bắt buộc, thư mục cấu hình Nginx và module `http_realip_module`.
- Kiểm tra cấu hình Nginx trước khi áp dụng hiển thị trực tiếp lỗi cú pháp nếu có thay vì ẩn vào `/dev/null`; thông báo rõ khi Nginx chưa active.
- Tự động tạo thư mục sao lưu `/var/backups/kwvps` với quyền root `0700` trước khi sao lưu file cấu hình Real IP cũ, tránh lỗi quyền hoặc thiếu thư mục.

Release này không tự cập nhật VPS. Hãy tạo snapshot/backup và cập nhật qua menu KwVPS khi sẵn sàng thử.
