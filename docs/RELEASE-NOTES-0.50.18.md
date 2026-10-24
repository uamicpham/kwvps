# KwVPS 0.50.18 — Tunnel token theo site và tự cập nhật Real IP

- Menu **Cloudflare Tunnel → Cấu hình Tunnel → 2** chọn site bằng số rồi lưu/thay Tunnel token riêng. Mỗi site dùng file token root-only và `kwvps-cloudflared-<site-id>.service`; trạng thái, restart và log cho chọn connector theo số.
- Connector chung `cloudflared.service` của bản cũ nằm ở mục 6 và không bị đổi hoặc dừng khi nâng cấp. Route/DNS trên Cloudflare không tự chuyển sang connector mới.
- Khi xác nhận `y` để ghi nhận site dùng Tunnel, KwVPS tự cập nhật Cloudflare Real IP nếu cấu hình còn thiếu, kiểm tra Nginx và áp Real IP vào vhost của site. Site đã đánh dấu Tunnel có thể chọn lại để đồng bộ Real IP. Nếu không cập nhật hoặc kiểm tra được, chế độ site không chuyển sang Tunnel.
- Gỡ connector/token riêng cần chuyển route và đưa site về DNS trước. Đổi tên hoặc xóa site sẽ từ chối khi connector riêng còn tồn tại để tránh bỏ sót service/token.
- Backup cấu hình hiện chưa chứa Tunnel token, service riêng hoặc route Cloudflare. Giữ các thông tin này trong kho bí mật riêng khi chuyển VPS.

VPS đã cài có thể chọn **Quản lý Update → Kiểm tra / cập nhật KwVPS** rồi thoát và mở lại `sudo kwvps`. Bản cập nhật không tự đổi route, token hoặc chế độ của site đang chạy.
