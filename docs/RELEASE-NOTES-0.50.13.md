# KwVPS 0.50.13 — Laravel và firewall UFW

- Menu Firewall và Tunnel xử lý trường hợp UFW đang có rule ALLOW do KwVPS tạo: gỡ ALLOW trước khi thêm DENY, kiểm tra cả IPv4/IPv6, và thử phục hồi ALLOW nếu thao tác lỗi. Rule do người quản trị tạo ngoài KwVPS không bị tự xóa. Thông báo lỗi UFW được hiển thị để dễ chẩn đoán.
- Khi bật UFW, KwVPS nhận diện cổng SSH từ `sshd` và `ssh.socket` của systemd. Thêm đường dự phòng nếu `ufw insert 1` không dùng được trên bảng rule trống.
- Phân lại quyền site hỗ trợ symlink nội bộ an toàn và chuẩn hóa quyền `.env`/`storage` của Laravel; deploy chấp nhận HTTP 503 khi ứng dụng đang ở maintenance mode.
- Sửa truy vấn gói NodeSource cho Node.js build riêng của KwVPS. Bản cài mới bổ sung các PHP extension phổ biến.

Workflow phát hành kiểm thử Bash, ShellCheck, Bats và checksum gói trên Ubuntu 24.04. Chưa xác nhận lại thao tác đóng inbound trên VPS của bạn sau bản sửa cuối. Bản phát hành không tự cập nhật VPS; giữ snapshot/console cứu hộ khi thử thay đổi firewall.
