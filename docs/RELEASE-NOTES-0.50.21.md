# KwVPS 0.50.21 — Cấu hình Nginx riêng cho từng site

- Menu Nginx chỉnh file `/etc/nginx/kwvps-custom/<site-id>/custom.conf` bằng nano. KwVPS kiểm tra `nginx -t`, restart và hoàn tác nếu lỗi; các directive định danh site, PHP socket, TLS và Real IP vẫn do KwVPS quản lý.
- Vhost HTTP/HTTPS do KwVPS tạo include file riêng trong server phục vụ ứng dụng. Site từ bản cũ vẫn được nhận diện. Khi vhost đã sửa tay, menu hiển thị diff để người quản trị xem và chuyển các directive cần giữ vào file riêng trước khi xác nhận dùng vhost mẫu; bản vhost cũ được lưu root-only. Vhost không nhận diện an toàn hoặc đang có FastCGI cache không được chuyển tự động.
- File riêng được giữ khi đổi tên miền, thay SSL, triển khai Laravel, bật/tắt FastCGI cache, đưa site vào vùng giữ và phục hồi. Khi đổi tên miền, KwVPS từ chối file còn tham chiếu domain hoặc site ID cũ để tránh cấu hình sót lại.
- Backup cấu hình mới chứa `custom.conf` nếu site đã dùng file riêng; restore kiểm tra file và hoàn tác khi Nginx lỗi. Site chưa chuyển vẫn backup nguyên `vhost.conf` kiểu cũ; các bản backup đã tạo không tự đổi định dạng.

Sau khi phát hành, VPS đã cài có thể chọn **Quản lý Update → Kiểm tra / cập nhật KwVPS** rồi mở lại `sudo kwvps`. Cập nhật chỉ thay mã KwVPS; vhost hiện có không tự bị sửa. Backup cấu hình vẫn không chứa source, database, SSL private key, Tunnel token hoặc cron toàn VPS.
