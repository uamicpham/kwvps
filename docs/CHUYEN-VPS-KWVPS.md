# Chuyển site KwVPS sang VPS khác — thiết kế đang triển khai

Backup cấu hình hiện tại **chưa** là gói chuyển VPS. Nó chỉ chứa metadata site, PHP pool và Nginx vhost. Không dùng bản này với kỳ vọng khôi phục website hoàn chỉnh trên máy mới.

Gói chuyển VPS mới phải được mã hóa bằng mật khẩu người dùng tự đặt và có kiểm tra toàn vẹn. Gói cần chứa source/code (bao gồm `.env`), cấu hình site, PHP pool, Nginx, SSL/private key, trạng thái ingress, rate limit, Zone ID, Cloudflare API token, Tunnel token, các thiết lập cache liên quan và bản crontab để khôi phục. Database/dump không nằm trong gói; người dùng khôi phục DB riêng. Bí mật không được in ra menu/log hoặc lưu trong Git.

Theo lựa chọn của người dùng, khi restore sẽ **tự kích hoạt** cấu hình phù hợp ngay sau kiểm tra và xác nhận `y/N`, thay vì chỉ lưu trạng thái chờ. Vì cron và Tunnel token có thể dùng chung nhiều site, restore phải từ chối ghi đè cấu hình toàn VPS đã tồn tại hoặc xung đột; không được ghép hoặc thay root crontab âm thầm. Cần cảnh báo rõ nguy cơ hai VPS cùng chạy cron/Tunnel khi máy cũ chưa tắt.

DNS, Cloudflare Tunnel route, zone rule và trạng thái ban IP là tài nguyên từ xa, không thể khẳng định đã được chuyển chỉ bằng bản sao file local. Trước khi báo “hoạt động bình thường”, phải thử hostname công khai, PHP, cache, SSL/renewal và backup DB đã restore trên VPS mới. SSL Let’s Encrypt HTTP-01 có thể cần cập nhật route/DNS hoặc cấp lại; sao chép chứng chỉ hiện tại không tự tạo cơ chế gia hạn mới.

Đổi tên miền trên cùng VPS cũng phải xét các tài nguyên này. Bản hiện tại chỉ đổi site HTTP nguyên mẫu, metadata DB tự đặt tên và Nginx rate limit local khi đã xác nhận DNS trực tiếp; không đổi tên DB/user. Nhãn ingress của site được chuyển nếu có, nhưng route Tunnel/DNS trên Cloudflare không tự đổi và có thể gây gián đoạn đến khi người dùng cập nhật. Site có Cloudflare push/rule, Zone ID, SSL hoặc cấu hình tùy biến vẫn bị từ chối thay vì đổi nửa chừng. URL trong ứng dụng không thể tự suy luận an toàn từ Nginx config.
