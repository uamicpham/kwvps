# KwVPS 0.50.4 — sửa cài PHP 7.4 từ PPA Ondřej

Khi Ubuntu 24.04 chọn `php-common` của kho mặc định và báo xung đột với `php7.4-common` của PPA Ondřej, KwVPS nay thử phiên bản `php-common` từ đúng PPA này. Trước khi cài, KwVPS kiểm tra nguồn gói, mô phỏng lại toàn bộ kế hoạch APT với `--no-remove`, từ chối mọi kế hoạch gỡ gói và cảnh báo rằng `php-common` dùng chung có thể ảnh hưởng các phiên bản PHP khác.

PHP 7.4 đã hết hỗ trợ bảo mật; bản sửa này chỉ giải quyết phụ thuộc gói, không làm PHP 7.4 an toàn cho website Internet. Các thay đổi phiên bản trước vẫn áp dụng.
