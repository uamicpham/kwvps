# KwVPS 0.50.1 — bộ cài Ubuntu 24.04 ghim phiên bản

Bản phát hành này bổ sung kiểm tra x86_64 trong bộ cài và bootstrap; lệnh cài một dòng ghim `v0.50.1` thay vì tự chọn release mới nhất. Bootstrap xác minh SHA-256 của gói do GitHub Release API công bố và kiểm tra archive trước khi chạy installer. Bộ cài từ chối VPS có KwVPS/web stack hoặc control panel sẵn và yêu cầu nhập `INSTALL KWVPS` trước khi cài package.

Chỉ hỗ trợ **Ubuntu Server 24.04 LTS sạch, x86_64, systemd**. Repo public không cần GitHub token để tải; Cloudflare/Tunnel token chỉ lưu trực tiếp trên VPS qua menu nếu dùng tính năng liên quan. Sau cài chạy `kwvps --doctor`, sau đó `kwvps`.

Chưa kiểm thử cài mới đầu-cuối trên VPS trắng thứ hai. SSH đổi port/key-only còn tạm gác; PHP 7.4 EOL bị chặn; ionCube chưa kiểm thử loader thật. Backup cấu hình không bao gồm DB, source, SSL private key, Cloudflare token hay cron. Đổi tên site chỉ hỗ trợ HTTP nguyên bản và không tự đổi DNS/route Cloudflare hoặc URL ứng dụng. Cần snapshot, backup độc lập và console cứu hộ trước khi dùng với dữ liệu quan trọng.
