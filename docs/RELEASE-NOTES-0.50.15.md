# KwVPS 0.50.15 — sửa cập nhật từ bản phát triển

- Sửa so sánh phiên bản để `0.50.15-dev` được coi là bản phát triển trước `0.50.15`. Kiểm tra này áp dụng cho cả menu cập nhật GitHub và `upgrade.sh`.
- Bao gồm các thay đổi của [0.50.14](RELEASE-NOTES-0.50.14.md): site mới dùng DNS thông thường, chọn chế độ Tunnel theo site và Laravel Deploy tự pull với tùy chọn migration.

Khi cập nhật trên VPS đang chạy `0.50.14-dev`, chọn **Quản lý Update → Kiểm tra / cập nhật KwVPS**, xác nhận bản `0.50.15`, rồi thoát và mở lại `sudo kwvps`. Lệnh cập nhật chỉ thay bộ mã; bản cũ được giữ tại `/opt/kwvps-previous-*`.

Workflow phát hành chạy Bash syntax, smoke, ShellCheck, Bats, đóng gói và kiểm tra SHA-256 trên Ubuntu 24.04. Kiểm thử migration đầu-cuối trên VPS có website thật vẫn cần thực hiện riêng.
