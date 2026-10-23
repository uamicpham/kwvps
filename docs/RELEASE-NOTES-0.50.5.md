# KwVPS 0.50.5 — token Cloudflare theo zone, sửa rate limit local

- Menu Cloudflare có **Thêm/thay token theo zone**: chọn site, nhập Zone ID và token của đúng tài khoản Cloudflare. KwVPS xác minh token còn active, đọc được zone và site thuộc zone rồi mới lưu root-only. Hai zone khác tài khoản có thể dùng hai token khác nhau. Token chung cũ vẫn được dùng nếu zone chưa có token riêng, để không phá cấu hình cũ; token riêng luôn được ưu tiên.
- Các thao tác Under Attack, Rate Limiting và worker đẩy IP bị Nginx giới hạn chọn token theo Zone ID. Tự tìm Zone ID chỉ dùng token chung cũ; với token riêng, nhập Zone ID một lần khi lưu token.
- Rate limit Nginx local không cần API token. KwVPS tự tạo thư mục cấu hình Cloudflare root-only nếu chưa có, đồng thời báo rõ lỗi Real IP, ingress và kiểm tra Nginx thay vì chỉ hiện mã 2.

Token vẫn là bí mật chỉ lưu trên VPS; đừng gửi vào chat. PHP 7.4 vẫn EOL như bản trước.
