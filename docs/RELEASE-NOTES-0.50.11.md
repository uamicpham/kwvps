# KwVPS 0.50.11 — Laravel deploy và Real IP qua Tunnel

- Deploy Laravel chuyển thư mục làm việc sang `/` trước khi chạy dưới user site, tránh lỗi `find` khi quản trị viên mở menu từ `/root`. `deploy/current` chỉ được kích hoạt sau khi build và kiểm tra quyền hoàn tất; vhost KwVPS nguyên bản tự chuyển sang `deploy/current/public`, kiểm tra/restart Nginx và health check.
- Menu build frontend gọn thành tự nhận từ lockfile, bỏ qua nếu assets đã có, hoặc chọn npm/pnpm/yarn trong mục nâng cao.
- Khi Node/npm toàn VPS quá cũ, menu công cụ có thể cài Node.js 24 riêng cho KwVPS, không thay runtime toàn hệ thống. Chưa kiểm thử cài gói này đầu-cuối trên VPS production.
- Site dùng Cloudflare Tunnel có cấu hình Real IP riêng trong vhost: tin connector trên `127.0.0.1`/`::1` và dùng `CF-Connecting-IP`; danh sách IP proxy Cloudflare công khai vẫn ở file toàn cục. Đây là thay đổi cấu hình cần kiểm tra trên từng site trước khi áp dụng production.
- Mở menu thiếu quyền root sẽ báo chạy `sudo kwvps`.

Release này không tự cập nhật VPS. Hãy tạo snapshot/backup và cập nhật qua menu KwVPS khi sẵn sàng thử. Chưa xác minh luồng deploy Laravel hoặc IP khách thật trên VPS production sau bản sửa này.
