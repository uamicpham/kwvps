# KwVPS 0.50.20 — Deploy Key và đổi tên site Laravel/Tunnel

- Laravel Clone/Pull qua SSH chỉ định Deploy Key `id_ed25519` của user site và kiểm tra owner/quyền trước khi kết nối. Nếu GitHub từ chối, menu chỉ ra user site và repository để đối chiếu public key; khóa riêng không được in ra.
- Đổi tên miền hỗ trợ vhost HTTP mẫu và Laravel release do KwVPS tạo, giữ document root `deploy/current/public` và lớp Real IP Tunnel. Sau đổi tên, cần cập nhật `APP_URL` cùng các thiết lập domain của ứng dụng.
- Khi đổi tên site HTTP do KwVPS quản lý, connector Tunnel riêng được chuyển sang site ID mới. Token giữ nguyên, service mới giữ trạng thái enabled/active của service cũ.
- KwVPS kiểm tra unit và quyền token trước khi đổi, dừng connector cũ trước khi khởi động connector mới, và thử phục hồi service/token cũ nếu giao dịch đổi tên thất bại. Bản sao token cũ nằm trong vùng backup root-only của lần đổi tên.
- Hostname route/DNS trên Cloudflare vẫn do người quản trị cập nhật; KwVPS không gọi Cloudflare API để sửa route. Site có vhost SSL, FastCGI cache hoặc cấu hình Nginx tùy biến vẫn bị từ chối bởi chức năng đổi tên.

Sau khi Release được công bố, VPS đã cài có thể chọn **Quản lý Update → Kiểm tra / cập nhật KwVPS**, rồi thoát và mở lại `sudo kwvps`. Menu Update chỉ thay bộ mã KwVPS; không tự đổi domain, route Cloudflare hoặc `.env`.
