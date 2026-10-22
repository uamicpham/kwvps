# KwVPS 0.50.3 — tùy chọn PHP 7.4 cho site cũ

Cho phép cài PHP 7.4-FPM và các extension thông dụng từ PPA Ubuntu `ppa:ondrej/php`, không dùng kho Debian `deb.sury.org`. Người quản trị phải xác nhận cảnh báo EOL trước khi cài và thêm một xác nhận riêng mỗi khi chọn PHP 7.4 để tạo, nhân bản, đổi tên hoặc chuyển site.

PHP 7.4 vẫn được đánh dấu chưa xác minh bản vá; xác nhận này chỉ bỏ chặn theo yêu cầu tương thích ứng dụng cũ, không có nghĩa phiên bản an toàn. Không khuyến nghị chạy website Internet bằng PHP 7.4. PHP 8.3/8.4/8.5 tiếp tục áp dụng kiểm tra bản vá như trước.

Gói PHP vẫn chỉ cài bộ extension thông dụng do KwVPS liệt kê, không phải toàn bộ extension có thể có. Xem candidate, nguồn APT và mô phỏng kế hoạch trước khi xác nhận cài.

Các thay đổi phiên bản trước vẫn áp dụng; chỉ dùng trên Ubuntu Server 24.04 x86_64 đã chuẩn bị theo hướng dẫn.
