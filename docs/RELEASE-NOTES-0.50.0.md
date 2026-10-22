# KwVPS 0.50.0 — bản phát hành công khai đầu tiên

Phạm vi cài mới: **Ubuntu Server 24.04 LTS sạch, x86_64, dùng systemd**. Không cài đè LarVPS, aaPanel, Nginx/Apache sẵn có hoặc VPS đang chứa website/dữ liệu. Bộ cài kiểm tra môi trường và yêu cầu nhập `INSTALL KWVPS` trước khi cài các gói hệ thống.

Sau khi cài, chạy `kwvps --doctor`, rồi `kwvps` để mở menu. Repo public không cần GitHub token để tải bản phát hành. Cloudflare API token và Tunnel token chỉ cần khi dùng các tính năng tương ứng; lưu trực tiếp trên VPS qua menu, không gửi trong chat hoặc đưa vào GitHub.

Gói tải là `kwvps-0.50.0.tar.gz`, có file SHA-256 đi kèm. Bootstrap kiểm tra digest do GitHub Release API công bố và kiểm tra thành phần archive trước khi chạy bộ cài. Chỉ dùng lệnh cài một dòng được ghim checksum bootstrap trong README sau khi release hoàn thành; không chạy mã từ nhánh `main` bằng `curl | bash`.

Giới hạn đã biết: SSH đổi port/key-only chưa mở trong menu; PHP 7.4 EOL bị chặn; ionCube chưa có kiểm thử loader thực tế. Backup cấu hình domain không phải gói di trú toàn bộ VPS và không gồm DB, source, SSL private key, Cloudflare token hoặc cron. Đổi tên site chỉ hỗ trợ vhost HTTP nguyên bản và không tự đổi DNS, URL ứng dụng hoặc route Cloudflare. Các mục này hiện thông báo phạm vi/giới hạn, không được xem là đã hoàn thành.

Trước khi dùng với dữ liệu quan trọng, cần backup độc lập, snapshot, console cứu hộ và thử quy trình phục hồi. Bản phát hành này không chứng nhận tương thích với Ubuntu 22.04, Debian hay VPS đã có web stack.
