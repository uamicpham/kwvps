# KwVPS 0.50.2 — sửa bộ cài thoát im lặng sau APT

Sửa lỗi đọc bản PHP-FPM ứng viên từ APT: bộ cài cũ có thể nhận mã `141` (SIGPIPE) khi kết hợp `awk` dừng sớm với `pipefail`, rồi thoát ngay sau `apt-get update` mà không cài package hay tạo lệnh `kwvps`. Bản mới đọc hết kết quả APT trước khi chọn Candidate. Cùng cách đọc này được áp dụng cho cập nhật service và kế hoạch cài phpMyAdmin.

Bộ cài nay báo rõ khi APT hoặc bước đọc Candidate thất bại; người dùng hủy xác nhận sẽ nhận mã thoát 130. Không thay đổi site hoặc dữ liệu trên VPS đã có KwVPS. Lệnh cài ngắn trong README tự chọn release mới nhất và sẽ lấy bản này; chỉ dùng trên Ubuntu Server 24.04 sạch, x86_64, systemd.

Chưa kiểm thử cài mới đầu-cuối trên VPS trắng thứ hai. Trước khi cài trên VPS có dữ liệu quan trọng, cần snapshot, backup độc lập và console cứu hộ. Các giới hạn chức năng của 0.50.1 vẫn áp dụng.
