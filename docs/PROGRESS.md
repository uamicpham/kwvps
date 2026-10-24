# Tiến độ KwVPS

## 0.50.13 — 24/10/2026

- **Quản lý site & Phân quyền:**
  - Hỗ trợ an toàn symlink nội bộ trong site root khi phân lại quyền (`kw_site_permissions`); kiểm tra chống vượt khỏi `$KW_SITE_ROOT` bằng script Python; không còn từ chối các site chứa symlink nội bộ của Laravel (`deploy/current`, `deploy/shared/storage`, `.env`).
  - Tự động phân quyền bảo mật chuyên sâu cho Laravel: gán `0600` cho `deploy/shared/.env` (chỉ user site sở hữu) và `0750` cho thư mục / `0660` cho file trong `deploy/shared/storage` (nhóm `www-data` ghi log/cache).
  - Loại bỏ rào cản hardlink (`-type f -links +1`) để tương thích trơn tru với các dự án frontend dùng `pnpm`, Git hoặc file giải nén có nhiều liên kết.
- **Triển khai Laravel:**
  - Khắc phục tìm kiếm gói NodeSource cô lập (`kw_laravel_nodesource_isolated_candidate`): thêm cờ `-o Dir::Cache::pkgcache=`, tạo thư mục `partial/` tạm và hỗ trợ regex URL có dấu gạch chéo cuối.
  - Cho phép mã phản hồi HTTP 503 trong health check sau deploy (`kw_laravel_health`) để nhận diện chính xác chế độ bảo trì (Maintenance Mode) của Laravel thay vì kích hoạt rollback nhầm.
  - Bổ sung đầy đủ các PHP extensions chuẩn vào bộ cài đặt ban đầu trong `install.sh` (`mysql`, `mbstring`, `xml`, `curl`, `zip`, `gd`, `intl`, `bcmath`).
- **Firewall UFW & Tunnel Inbound:**
  - Bảo vệ SSH thông minh khi kích hoạt UFW (`kw_fw_ssh_ports`): tự động đọc cổng lắng nghe từ socket systemd (`systemctl show ssh.socket -p Listen`) kết hợp với cấu hình `sshd_config`; không còn từ chối bật UFW trên Ubuntu 24.04 khi chạy lệnh qua `sudo` làm mất biến `$SSH_CONNECTION`.
  - Cơ chế dự phòng khi bảng rule UFW trống: tự động chuyển từ `ufw insert 1` sang `ufw allow` / `ufw deny` thông thường, loại bỏ triệt để lỗi `ERROR: Invalid position '1'`.
  - Menu Inbound 80/443 hiển thị thông báo rõ ràng cho người dùng khi UFW đang tắt trước khi yêu cầu xác nhận `y/N`.
  - Smoke test cục bộ nâng lên 628/628 checks đạt PASS.

## 0.50.12 — 24/10/2026

- Cải thiện kiểm tra và thông báo lỗi cho menu Cập nhật Cloudflare Real IP: kiểm tra quyền root ngay khi vào menu tương tác, cảnh báo chạy `sudo kwvps`.
- Ghi log chi tiết cho từng tiền kiểm tra thất bại: OS không hỗ trợ, thiếu install-id, thiếu công cụ hệ thống, thư mục nginx conf.d hoặc module Nginx realip.
- Hiển thị trực tiếp lỗi cú pháp Nginx nếu có thay vì nuốt vào `/dev/null`; thông báo rõ khi Nginx chưa active.
- Tự động tạo thư mục `/var/backups/kwvps` quyền 0700 trước khi sao lưu file cấu hình Real IP cũ.

## 0.50.11 — 24/10/2026

- Sửa deploy Laravel chạy từ thư mục `/` trước khi hạ quyền sang user site; tránh lỗi `find` khi menu được gọi từ `/root`. `deploy/current` chỉ xuất hiện sau khi Composer/frontend/quyền file hoàn tất, ngay trước bước đổi vhost và health check. Menu build còn hai lựa chọn thường dùng (tự nhận/bỏ qua); npm, pnpm, yarn nằm dưới mục nâng cao.
- Bổ sung đường cài Node.js 24 riêng cho build KwVPS khi VPS đã có Node/npm cũ: xác minh khóa/chỉ mục APT NodeSource và SHA-256 gói, giải nén vào `/usr/local/lib/kwvps/nodejs`, không thay Node toàn hệ thống. Chưa thử cài đầu-cuối trên VPS thật.
- Site được đánh dấu Tunnel có thể nhận `CF-Connecting-IP` từ connector loopback trong vhost riêng; file CIDR toàn cục vẫn chỉ tin IP proxy Cloudflare công khai. Đổi mode và cập nhật Real IP kiểm tra `nginx -t`, restart và có rollback. Tiến trình local truy cập loopback cùng vhost vẫn có thể giả header, nên cần cách ly origin nếu site chạy mã không tin cậy.
- Smoke cục bộ đạt 626 phép kiểm tra và 9 kiểm tra hệ thống mô phỏng. Chưa áp lên VPS production và chưa xác minh request thật qua Tunnel sau bản sửa này.

## 0.50.1 — bộ cài ghim release, 22/10/2026

- GitHub Release `v0.50.0` đã tạo công khai; bản 0.50.1 bổ sung kiểm tra x86_64 và cho bootstrap chọn tag cố định. 531 smoke, 9 system, 172 Bats, 2 Python, ShellCheck và checksum package đã đạt trên bản sao ở VPS lab.
- Chưa cài mới đầu-cuối trên VPS trắng thứ hai. VPS lab đang chạy 0.49.2-dev và không bị cài đè.

## 0.50.0 — ứng viên phát hành Ubuntu 24.04, 22/10/2026

- Giới hạn bộ cài một dòng cho Ubuntu Server 24.04 LTS sạch, x86_64 và systemd. Gói sẽ được xuất bản từ GitHub Actions theo tag sau khi toàn bộ kiểm thử đạt; lệnh cài sẽ ghim checksum bootstrap và xác minh SHA-256 gói phát hành.
- Sửa menu Tunnel cho phép xem hướng dẫn/thoát bằng tài khoản thường, vẫn giữ kiểm tra root ở các hành động ghi. Đây là nguyên nhân Bats trên GitHub (runner không phải root) thất bại; 167/167 Bats đã đạt trên VPS lab khi chạy bằng tài khoản `nobody`.
- Chưa tạo tag hoặc công bố lệnh cài ở thời điểm ghi mục này. Chưa chạy cài mới đầu-cuối trên VPS thứ hai sạch; không coi các bài test unit là thay thế kiểm thử cài mới thực tế.

## 0.49.2-dev — Menu, cập nhật và chuẩn bị phát hành, 22/10/2026

- Đã căn lại tiêu đề/breadcrumb tiếng Việt, đường kẻ và hướng dẫn thao tác menu. Menu con không lặp thông tin tài nguyên VPS.
- Cập nhật Ubuntu và service qua menu nay làm mới APT trước khi lập kế hoạch; từ chối candidate PHP-FPM chờ nâng nếu chưa được xác minh bản vá. Menu KwVPS có cấu hình GitHub `owner/repo` public và đường đọc release ổn định, kiểm tra SHA-256 + thành phần archive trước nâng; vẫn giữ đường gói local root-only khi chưa cấu hình repo. Chưa có repo/release thật nên đường GitHub chưa được thử đầu-cuối.
- Bộ cài kiểm tra sự đầy đủ/cú pháp source trước khi cài package; có script tạo archive release từ danh sách file cố định, chỉ nhận phiên bản ổn định `x.y.z` và từ chối ghi đè artifact. Bootstrap release public đã có kiểm tra SHA-256 và archive; khi công bố lệnh một dòng còn phải ghim bootstrap theo commit + checksum. Bản dev hiện tại cố ý chưa đóng gói chính thức.
- Trên VPS lab: làm mới APT thành công; không có gói Nginx/PHP-FPM/MariaDB/Redis/Fail2ban/UFW/Cloudflared chờ nâng, còn 7 gói Ubuntu khác chờ update và chưa áp dụng. Đã nâng **chỉ bộ mã KwVPS** từ `0.49.1-dev` lên `0.49.2-dev`; mã trước giữ tại `/opt/kwvps-previous-20261022T104826Z-k6bjDPgd`. `kwvps --doctor`, `nginx -t`, danh sách 3 site đạt sau nâng.
- 531 smoke, 9 system, 167 Bats và 2 Python tests đạt trên staging. ShellCheck toàn bộ mã shell đạt. Rà chuỗi bí mật đã thay token mẫu bằng dữ liệu tổng hợp trong test; `.gitignore` bổ sung key/certificate và `dist/`. Đây chưa phải kiểm định bảo mật độc lập hay xác nhận toàn bộ chức năng sẵn sàng production; SSH port/key-only và ionCube thực tế vẫn thiếu kiểm thử/triển khai.

## 0.49.1-dev — PHP 8.4/8.5 trên VPS lab, 22/10/2026

- Đã nâng KwVPS trên VPS Ubuntu 24.04.4 từ `0.49.0-dev` lên `0.49.1-dev`; mã trước giữ tại `/opt/kwvps-previous-20261022T101933Z-fSpFsbbO`. Khi gói PHP từ PPA cần `php-common` mới hơn bản Ubuntu, menu chỉ chọn bản Ondřej đã xác minh nguồn/phiên bản, mô phỏng lại APT với `--no-remove` và cảnh báo tác động tới PHP dùng chung.
- Đã cài PHP-FPM 8.5.12 và 8.4.27 cùng extension từ `ppa:ondrej/php`; `php-common` được nâng từ `2:93ubuntu2` lên `2:101~+ubuntu24.04.1+deb.sury.org+1`. PHP 8.3 của Ubuntu vẫn là candidate và FPM 8.3/8.4/8.5 đều active, kiểm tra cấu hình đạt. Lệnh `php` CLI mặc định toàn VPS chuyển từ 8.3 sang 8.5 do APT auto-alternatives; FPM từng site không tự đổi.
- Tạo site `.test` với PHP 8.4, kiểm tra socket/HTTP 200; chuyển site đó sang PHP 8.5, socket/HTTP 200 vẫn đạt. Sau thử đã **xóa sạch** riêng site `php-matrix.kwvps.test`, không giữ vùng phục hồi; hai backup pool/metadata độc lập và log thử vẫn được giữ theo chính sách KwVPS. Ba site có trước vẫn nguyên, `kenhgamez.cc` trả HTTP 200, Nginx và cả ba FPM active.
- 525 smoke, 9 system, 161 Bats, 2 Python tests và ShellCheck toàn repo đạt trên staging. PHP 7.4 tiếp tục bị chặn vì EOL, chưa xác minh backport bản vá cho gói cụ thể.

## 0.49.0-dev — Dọn log, PHP PPA an toàn, kiểm tra trùng tên miền

- Menu Logs có phạm vi dọn file access/error KwVPS, PHP-FPM và journal cũ toàn VPS riêng biệt; xem kế hoạch và xác nhận `y/N`, sau đó liệt kê thư mục/số file/dung lượng xử lý. File đang ghi giữ inode, không xóa thư mục; Ubuntu logrotate vẫn là cơ chế giới hạn dài hạn.
- Menu cài PHP 8.4/8.5 có thể thêm PPA Ubuntu `ppa:ondrej/php` khi kho chính thức chưa có gói đạt ngưỡng, xác nhận riêng trước khi thêm nguồn và trước khi cài. Kiểm nguồn gói, phiên bản vá và mô phỏng APT. PHP 7.4 chưa được xác minh bản vá nên vẫn chặn.
- Đổi tên miền không còn nhận nhầm domain gốc là trùng vì xuất hiện trong subdomain/certificate path. Site có ingress chưa phân loại được đổi cấu hình local sau cảnh báo route Cloudflare/DNS phải cập nhật riêng. Chặn gói nâng cấp KwVPS cũ hơn bản đã cài.
- Đã nâng VPS lab lên `0.49.0-dev`, bản trước tại `/opt/kwvps-previous-20261022T100652Z-HdTWgzeK`. Luồng `kenhgamez.cc` → `kenhgamez.top` vượt preflight đến bước xác nhận; đã chọn **không**, nên domain/site thật chưa đổi. Kiểm tra log cleanup chỉ xem kế hoạch và chọn **không**, chưa xóa log VPS. PPA Ondřej đã được thêm và ghim ưu tiên 100; bản 0.49.0 phát hiện đúng rằng PHP 8.5 cần nâng `php-common` nhưng chưa xử lý phụ thuộc này, nên dừng trước khi cài gói PHP; bản 0.49.1 khắc phục.

## 0.44.0-dev — Làm rõ anti-DDoS, API và Tunnel (đã nâng VPS)

- Menu anti-DDoS nói rõ hiện chỉ trả 429 tại Nginx, không đẩy IP hoặc tạo block/challenge trên Cloudflare. Token Cloudflare tại menu Bảo mật/Cloudflare mục 4 hiện dùng cho Under Attack; Tunnel token riêng. Ban theo hostname cần xác minh IP thực, đếm vi phạm, allowlist, WAF rule `hostname + IP`, lưu rule ID và thời hạn, tự gỡ đúng rule KwVPS tạo; cần quyền Zone WAF Write và kiểm thử sau.
- Tunnel có thể hoạt động khi đóng **inbound** 80/443, nếu route, local origin và SSL/ACME đã được kiểm chứng; cần **outbound** 7844. KwVPS không tự đóng cổng. Vì Real IP qua connector loopback chưa được xác minh, bản này chặn bật rate limit local đồng thời với cloudflared active.
- Staging đạt 514 smoke, 9 system, 131 Bats và ShellCheck. Đã nâng VPS lên 0.44.0-dev; giới hạn 10 req/s do người dùng bật vẫn giữ nguyên, cloudflared inactive, Nginx/MariaDB/Redis active. Bản cũ ở `/opt/kwvps-previous-20261022T044547Z-R7IsWqRh`.

## 0.43.0-dev — Cài và cấu hình Cloudflare Tunnel (đã nâng VPS)

- Menu Tunnel mục 1 hiển thị tùy chọn cài khi chưa có `cloudflared`, dùng kho APT chính thức Cloudflare Noble sau xác nhận. Khi đã cài, hiện hướng dẫn tạo Tunnel/route theo site, lưu token riêng root-only và tạo service dùng `--token-file`; không đưa token vào lệnh chạy hay tự đóng 80/443. Từ chối ghi đè service Cloudflare không do KwVPS quản lý.
- VPS lab đã cài `cloudflared` 2026.10.3; nhánh menu sau cài đúng. Chưa có Tunnel token nên **chưa tạo service hoặc kiểm tra route thật**. Nginx/MariaDB/Redis vẫn active. Staging đạt 514 smoke, 9 system, 130 Bats, ShellCheck. Bản trước ở `/opt/kwvps-previous-20261022T043735Z-0y7OsOr4`.

## 0.42.0-dev — Anti-DDoS local theo domain (đã nâng VPS)

- Menu Cloudflare mục 2 chọn site bằng số và áp mức 5/10/20/50 request/giây hoặc tắt. Cấu hình Nginx global dùng `map $host` để chỉ giới hạn hostname được chọn; dựa trên Real IP đã có, trả HTTP 429, kiểm tra `nginx -t`, reload và hoàn tác lỗi. Không đóng cổng hoặc đổi vhost.
- VPS lab: HTTPS loopback `kwvps.kenhgamez.top` ở mức 5 req/s trả 14 lần 200, 26 lần 429 trên 40 request; đã tắt lại, Nginx active và cú pháp đạt. Đây là rate limit local, không ngăn bypass origin/không tự ban Cloudflare. 513 smoke, 125 Bats, ShellCheck đạt; bản cũ `/opt/kwvps-previous-20261022T042626Z-2pqL4KsZ`.

## 0.41.0-dev — Cập nhật KwVPS từ gói local (đã nâng VPS)

- Menu Update mục 1 dùng `/root/kwvps-update` root-only, từ chối symlink/owner hoặc quyền không an toàn, chạy kiểm tra trước xác nhận nâng cấp. Chưa tự tải GitHub vì chưa có repository/release. Đã nâng VPS từ 0.40 lên 0.41; bản cũ `/opt/kwvps-previous-20261022T041927Z-41yTC3Ef`.

## 0.40.0-dev — FastCGI cache theo domain (đã nâng VPS)

- Menu Cache có xóa file cache domain, xem trạng thái domain, Redis và bật/tắt FastCGI theo site. Cache riêng trong `/var/cache/nginx/kwvps/<site-id>`; chỉ lưu GET/HEAD ẩn danh không query/cookie/Authorization, tối đa 256 MB mỗi site, TTL 5 phút cho HTTP 200. Không xóa Redis hoặc cache ứng dụng.
- VPS lab: tạo `cachelab.kwvps.test`, bật cache; PHP request đầu `MISS`, lần kế `HIT`, cookie/query đều `BYPASS`; xóa đúng một file cache, tắt cache, Nginx đạt rồi xóa sạch site lab. Bản backup vhost độc lập còn trong `/var/backups/kwvps`; thư mục cache rỗng và map global có thể còn, không phục vụ site lab.
- Staging đạt 513 smoke, 9 system, 122 Bats và ShellCheck. Đã nâng VPS lên 0.40.0-dev; Nginx/PHP-FPM/MariaDB/Redis active. Bản mã cũ ở `/opt/kwvps-previous-20261022T041345Z-wRzgdPio`. Cache chưa bật trên site thật; cần kiểm thử ứng dụng đăng nhập/giỏ hàng trước khi dùng.

## 0.39.0-dev — phpMyAdmin (đã nâng VPS)

- Menu Tiện ích có ba mục. Gói phpMyAdmin Ubuntu, Nginx loopback `127.0.0.1:9080`, pool PHP-FPM riêng và chính sách cookie login, từ chối root/passwordless. Người dùng truy cập từ PuTTY SSH tunnel, không mở cổng public.
- Staging đạt 513 smoke, 9 system, 118 Bats và ShellCheck. VPS lab đã thử tạo user `kwvps_admin@localhost`, đăng nhập và nhìn thấy mọi DB, sau đó tự xóa user/marker lab. Đã nâng VPS lên 0.39.0-dev, bản cũ tại `/opt/kwvps-previous-20261022T035853Z-wu9xQNhc`; sau đó tiếp tục nâng 0.40.

## 0.39.0-dev — phpMyAdmin (mã cục bộ, chưa nâng KwVPS trên VPS)

- Menu Tiện ích có kế hoạch/cài gói Ubuntu, endpoint Nginx chỉ nghe `127.0.0.1:9080`, PHP-FPM pool riêng, cấu hình từ chối root/passwordless và hướng dẫn dùng PuTTY SSH tunnel. Menu theo site liệt kê DB/user của site; menu admin có tạo hoặc đổi mật khẩu `kwvps_admin@localhost` qua xác nhận, không nhúng password vào URL.
- Trên VPS lab đã cài package `phpmyadmin` 5.2.1 từ Ubuntu. Lần setup đầu rollback do PHP-FPM socket chưa xuất hiện kịp; thêm chờ socket rồi setup lại, HTTP loopback trả 200. Không mở cổng public hoặc tạo tài khoản admin. KwVPS đang cài trên VPS vẫn là 0.38.0-dev; cấu hình phpMyAdmin lab hiện do mã staging tạo.
- Ba unit test phpMyAdmin và ShellCheck đã đạt trước sửa chờ socket. Bộ kiểm tra đầy đủ và test tạo/xóa tài khoản admin chưa chạy lại vì quyền phê duyệt kết nối VPS tạm thời hết hạn. Không xem 0.39 là bản đã phát hành/kiểm thử hoàn tất.

## 0.38.0-dev — ionCube (đã nâng mã lên VPS, chưa bật loader thật)

- Menu PHP → ionCube theo version có trạng thái, bật/tắt theo PHP-FPM version. File loader Linux x86-64 phải do quản trị viên lấy từ nguồn chính thức, đặt root-owned ở `/root/kwvps-loaders/ioncube_loader_lin_<version>.so` và nhập SHA-256 lấy độc lập. Kiểm tra hash, chạy thử với PHP CLI tương ứng, kiểm tra cấu hình FPM, reload và hoàn tác khi lỗi. PHP 7.4 vẫn bị chặn bởi chốt bản vá.
- Staging đạt 507 smoke, 9 system, 115 Bats và ShellCheck. Đã nâng VPS thử nghiệm lên 0.38.0-dev; Nginx config đạt, Nginx/PHP-FPM/MariaDB/Redis active. Bản cũ ở `/opt/kwvps-previous-20261021T202053Z-8WS0vhQa`. Chưa có loader thật để kiểm thử đường bật; không coi là xác nhận tương thích ionCube cho mọi version/site.

## 0.37.0-dev — ACME provider

- Chọn Let’s Encrypt hoặc ZeroSSL cho lần cấp mới. ZeroSSL dùng EAB nhập trên VPS và lưu root-only; không đổi chứng chỉ/renewal hiện có. Đã thử chọn Let’s Encrypt trên VPS, chưa có EAB để thử ZeroSSL thật.
- Staging đạt 507 smoke, 9 system, 114 Bats và ShellCheck; VPS đã nâng lên 0.37.0-dev, Nginx/PHP-FPM/MariaDB/Redis active, HTTPS site thật trả 200.

## 0.36.0-dev — đổi tên miền HTTP

- Đổi định danh, user, home, pool, vhost và metadata site HTTP nguyên bản, cập nhật liên kết metadata DB tự đặt tên; không đổi DB/user DB. Từ chối SSL, vhost/pool tùy biến, DB legacy và domain đích trong vùng giữ. Có backup và rollback.
- VPS đã thử đổi tên thành công, cố tình làm health check lỗi để chứng minh rollback, rồi thử site có DB metadata. Site/DB lab đã xóa; các bản backup độc lập được giữ. Staging đạt 506 smoke, 9 system, 111 Bats và ShellCheck.

## 0.35.0-dev — paid SSL, 22/10/2026

- Menu SSL có mục nhập paid SSL cho site KwVPS còn vhost HTTP nguyên bản. Fullchain/key PEM đặt trong `/home/ssl` do root sở hữu; private key chỉ root đọc. Trước khi áp, KwVPS kiểm tra hostname, hạn, public key khớp; lưu bản sao vhost, kiểm tra Nginx và HTTPS loopback, hoàn tác nếu lỗi. Không ghi đè TLS có sẵn hoặc tự gia hạn paid SSL.
- Site dùng paid SSL được nhận diện trong danh sách SSL và kế hoạch xóa site. Khi xóa site, cert/key vẫn giữ và được nêu rõ; người quản trị phải quản lý vòng đời chứng chỉ riêng.
- Đã thử trên site lab `paidssl.kwvps.test` với chứng chỉ tự ký (chỉ bài thử loopback bỏ qua kiểm tra CA), HTTPS trả 200. Sau thử đã xóa sạch site lab và dọn đúng bốn file cert/key tự ký cùng thư mục cert lab; backup vhost thử nghiệm độc lập vẫn được giữ. Site thật `kwvps.kenhgamez.top` trả HTTPS 200.
- Staging đạt 504 smoke checks, 9 system checks, 109 Bats tests và ShellCheck. VPS thử nghiệm đã nâng 0.34 → 0.35; bản cũ giữ tại `/opt/kwvps-previous-20261021T195125Z-yNaXtQPh`. Doctor, Nginx config và Nginx/PHP-FPM/MariaDB/Redis đều đạt sau nâng.
- Bản vá `0.35.1-dev` chỉ hiển thị paid SSL trong kế hoạch xóa khi vhost thực sự dùng chứng chỉ đó. VPS đã nâng từ 0.35; bản cũ giữ tại `/opt/kwvps-previous-20261021T195352Z-r3g9EGNo`. Smoke 504, system 9, 24 Bats liên quan và ShellCheck đạt; HTTPS site thật trả 200 sau nâng.

## Đang thực hiện — 22/10/2026

- Theo yêu cầu mới, tạm gác SSH. Mục key-only quay về trạng thái chưa triển khai trong menu; bản staging `0.33.0-dev` chưa phát hành lên VPS.
- Đã cập nhật mã cục bộ để chặn PHP-FPM chưa có bản vá cho CVE-2026-109618/109619 khi cài mới, tạo/clone site và đổi phiên bản PHP. Ngưỡng upstream là 8.5.12, 8.4.27, 8.3.36; riêng Ubuntu 24.04 backport PHP 8.3 là `8.3.6-0ubuntu0.24.04.13`. PHP 7.4 tạm bị chặn vì EOL và chưa xác minh bản vá từ gói cụ thể.
- VPS thử nghiệm đã nâng các gói PHP 8.3 liên quan từ revision `.12` lên `.13`. Mã `0.34.0-dev` đã qua 504 smoke checks, 9 system checks, 105 Bats tests và ShellCheck trên staging rồi nâng lên VPS. Sau nâng: doctor đạt, site vẫn hiện, Nginx config đạt, Nginx/PHP-FPM/MariaDB/Redis active, HTTPS site thử trả 200. Mã cũ ở `/opt/kwvps-previous-20261021T193856Z-kf7JAis8`.

## Tiêu chí phát hành chính thức

Người dùng muốn cài trên VPS sạch bằng một dòng lệnh tải release từ GitHub và sau đó dùng `kwvps`. Hiện chưa có GitHub repository, vì vậy chưa có URL/lệnh cài thật. Bộ cài cục bộ vẫn chỉ dành cho thử nghiệm; xem [quy trình phát hành](PHAT-HANH-GITHUB.md). Một phép thử tích hợp HTTP/PHP cơ bản đã đạt trên VPS riêng, nhưng chưa đủ điều kiện production; các chức năng sẽ công bố vẫn cần hoàn thiện và kiểm thử.

## Đang phát triển: 0.33.0-dev — chỉ cho phép AuthKey

- Mã và menu đã có trong workspace/staging, đạt 501 smoke checks, 9 system checks, 101 Bats tests và ShellCheck. Chưa nâng lên VPS; VPS đang ở `0.32.0-dev`.
- Bài áp dụng key-only thật bị lớp an toàn từ chối vì có nguy cơ khóa SSH khi thao tác kết thúc trước khi hoàn tác. Không thử lại bằng đường vòng. Cần quy trình kiểm thử có cơ chế tự hoàn tác và phê duyệt phù hợp trước khi công bố mục này là đã thử thật.

## 0.32.0-dev — quản lý API token Cloudflare trong menu, 22/10/2026

- Thêm Công cụ nâng cao → Bảo mật/Cloudflare → Cấu hình API token: xem trạng thái không lộ bí mật, thêm/thay token bằng nhập ẩn ký tự, và hướng dẫn tạo token quyền tối thiểu cho đúng zone. Token mới được xác minh với Cloudflare trước khi thay file root-only; token cũ giữ nguyên khi xác minh thất bại. Under Attack thiếu token chỉ đúng menu cần dùng.
- Staging đạt 500 smoke checks, 9 system checks, 100 Bats tests và ShellCheck. Đã xác minh/lưu lại chính token hiện có trên VPS thử nghiệm; so sánh byte-for-byte sau thao tác đạt, không hiển thị token.

## 0.31.0-dev — tự tìm Zone ID Cloudflare, 22/10/2026

- Khi site chưa có Zone ID lưu, KwVPS tìm zone phù hợp nhất bằng token có quyền Zone Read; chỉ hỏi ID thủ công nếu API không tìm được. Vẫn xác minh lại domain/zone, lưu root-only và xác nhận trước thay đổi mức bảo vệ.
- Staging đạt 497 smoke checks, 9 system checks, 96 Bats tests và ShellCheck. Trên VPS thử nghiệm đã tự tìm zone `kenhgamez.top`, xác minh site thuộc zone, lưu ID quyền `0600` và đọc được mức hiện tại. Không thay đổi mức bảo vệ trong phép thử.

## 0.30.0-dev — giới hạn đăng nhập SSH, 22/10/2026

- Menu SSH/AuthKey / Giới hạn đăng nhập cho đặt `MaxAuthTries` (2–10), `MaxSessions` (1–20), `LoginGraceTime` (30–120 giây) bằng drop-in riêng. Trước/sau ghi đều kiểm tra `sshd -t` và giá trị hiệu lực, reload `ssh`, lỗi trả bản cũ. Không đổi port hay phương thức xác thực.
- Staging đạt 497 smoke checks, 9 system checks, 94 Bats tests và ShellCheck. Đã áp thử chính các giá trị mặc định 6/10/120 trên VPS và đăng nhập SSH bằng phiên mới thành công; chưa siết giới hạn thực tế.

## 0.29.0-dev — nhớ Zone ID Cloudflare theo site, 22/10/2026

- Sau khi xác minh domain thuộc zone qua API, KwVPS lưu Zone ID vào file root-only `0600`; lần sau tự dùng lại và vẫn xác minh trước khi thao tác. Có mục đổi Zone ID đã lưu, không thay đổi mức bảo vệ khi chỉ đổi ID. Nếu file lưu sai quyền/nội dung, từ chối sử dụng.
- Staging đạt 497 smoke checks, 9 system checks, 92 Bats tests và ShellCheck. API token trên VPS đã xác minh hợp lệ; endpoint đọc zone hoạt động. Chưa áp lệnh thay đổi mức bảo vệ trong vòng test tự động này.

## 0.28.0-dev — quản lý Redis, 22/10/2026

- Menu Cache / Redis xem trạng thái và PING; nếu chưa cài, mô phỏng apt rồi mới cài khi xác nhận `y/N`. Sau cài kiểm tra service active, chỉ nghe loopback và PING local; nếu kiểm tra thất bại yêu cầu dừng service. Restart cần xác nhận, không xóa dữ liệu cache chung.
- Staging đạt 497 smoke checks, 9 system checks, 90 Bats tests và ShellCheck. Đã cài thử Redis từ gói Ubuntu trên VPS thử nghiệm: chỉ nghe loopback và PING thành công. Cache domain/FastCGI vẫn chưa triển khai.

## 0.27.0-dev — public key SSH và đổi mật khẩu, 22/10/2026

- Menu SSH/AuthKey có đổi mật khẩu qua `passwd` tương tác và quản lý public key ed25519 cho `root`/`ubuntu`: liệt kê fingerprint đánh số, thêm sau `y/N`, xóa theo số và nhập lại fingerprint, không xóa khóa cuối cùng. Từ chối file/symlink/quyền SSH không an toàn; thao tác dùng khóa và file tạm rồi thay nguyên tử. Không đổi cổng hoặc bật key-only ngầm.
- Staging đạt 495 smoke checks, 9 system checks, 85 Bats tests và ShellCheck. Đã thử thêm/xóa khóa tạm trên VPS thử nghiệm; nội dung `/root/.ssh/authorized_keys` sau thử khớp byte-for-byte bản đầu. Chưa thử đổi mật khẩu vì không muốn đổi mật khẩu đăng nhập hiện hành trong bài tự động.

## 0.26.0-dev — Cloudflare Under Attack theo zone, 22/10/2026

- Menu Under Attack chọn site, nhập Zone ID, xác minh domain thuộc zone qua Cloudflare API và cảnh báo thay đổi ảnh hưởng mọi hostname của zone. Token chỉ đọc từ `/etc/kwvps/cloudflare/token` (root `0600`); request dùng file cấu hình curl tạm thay vì để token trong tham số lệnh. Khi bật, lưu mức bảo vệ cũ; khi tắt, trả đúng mức đó, không mặc định tùy tiện.
- Staging đạt 494 smoke checks, 9 system checks, 82 Bats tests và ShellCheck. Chưa có token Cloudflare nên **chưa thử API thật hoặc bật Under Attack**. Cần người dùng đặt token quyền `Zone:Read` và `Zone Settings:Edit` trên VPS và cung cấp Zone ID (không gửi token trong chat).

## 0.25.0-dev — Cloudflare Real IP cho Nginx, 22/10/2026

- Menu Công cụ nâng cao → Cloudflare Real IP tải dải IPv4/IPv6 chính thức qua HTTPS, xác minh CIDR chuẩn, rồi ghi cấu hình Nginx bằng file tạm. `nginx -t` và reload thất bại sẽ trả bản trước. Chỉ tin header `CF-Connecting-IP` từ dải proxy Cloudflare; không mở/đóng port, không bật antiDDoS hoặc Under Attack.
- Staging đạt 493 smoke checks, 9 system checks, 78 Bats tests và ShellCheck. Đã áp thử trên VPS Ubuntu 24.04: cấu hình hợp lệ, Nginx reload thành công. Chưa thử request qua Cloudflare vì domain hiện để DNS only.
- Đã nâng VPS thử nghiệm lên `0.25.0-dev`; bản mã trước ở `/opt/kwvps-previous-20261021T170257Z-pFhYmfsl`. Sau nâng: Nginx/PHP-FPM/MariaDB active, `nginx -t` đạt và HTTPS site chính trả 200.

## 0.24.1-dev — cập nhật Ubuntu 24.04 có kế hoạch, 21/10/2026

- Menu Cập nhật Ubuntu mô phỏng `apt-get upgrade --no-remove`, từ chối kế hoạch gỡ package, xác nhận `y/N` trước khi áp dụng; không nâng bản Ubuntu và không tự reboot. Dựa trên cache apt hiện tại, không tự chạy `apt update`; package không có rollback tự động. Đường áp dụng thật chưa thử khi không có package chờ nâng.
- Staging đạt 492 smoke checks, 9 system checks, 75 Bats tests và ShellCheck.

## 0.24.0-dev — cập nhật package dịch vụ có kiểm soát, 21/10/2026

- Menu Cập nhật → Cập nhật service có kế hoạch apt trước khi ghi, xác nhận `y/N`, chỉ nâng package dịch vụ KwVPS đã cài. Nếu mô phỏng apt gỡ gói hoặc thay package ngoài danh sách, thao tác bị từ chối; không tự chạy `apt update` hay nâng toàn bộ Ubuntu. Sau nâng kiểm tra Nginx, nhưng không có rollback package tự động.
- Staging Ubuntu đạt 492 smoke checks, 9 system checks, 72 Bats tests và ShellCheck. VPS hiện không có package dịch vụ chờ cập nhật trong cache apt, nên chưa thử đường cài nâng thực tế.

## 0.23.0-dev — vòng đời site và domain trong vùng giữ, 21/10/2026

- Xóa Site có hai lựa chọn: giữ vùng phục hồi hoặc xóa sạch, không giữ vùng phục hồi. Cả hai yêu cầu nhập lại domain; không còn lựa chọn tạo backup source mới.
- Thêm domain đang trong vùng giữ đề nghị phục hồi hoặc xóa bản giữ rồi thêm mới. Phục hồi xác nhận `y/N`; xóa bản giữ yêu cầu nhập lại domain. DB/chứng chỉ/backup độc lập không bị xóa.
- Xóa sạch gói cuối cùng của một site cũng dọn user Linux không còn site hoặc gói giữ tham chiếu. Chưa coi bản này là production.
- Staging đạt 491 smoke checks, 9 system checks, 69 Bats tests và ShellCheck. Thử tích hợp trên `kwvps-lifecycle023.test`: tạo → giữ → phục hồi → giữ → xóa bản giữ và tạo mới → xóa sạch → tạo lại → xóa sạch. Phép thử đầu phát hiện thư mục vùng giữ rỗng cản dọn user; đã sửa và chạy lại đạt. Đã nâng VPS thử nghiệm lên `0.23.0-dev`; bản mã trước ở `/opt/kwvps-previous-20261021T164854Z-zuXVmPNh`. Sau nâng: Nginx/PHP-FPM/MariaDB active, `nginx -t` đạt, HTTPS site chính trả 200. Site `.test` và thư mục rỗng còn lại của phép thử đã được dọn.

## 0.22.0-dev — Cloudflare Tunnel restart, 21/10/2026

- Menu Tunnel có thao tác restart dịch vụ Cloudflared đang active sau xác nhận `y/N`; kiểm tra service sau restart và không tự thay firewall/cổng 80/443. Nếu service chưa cài/chưa active thì từ chối, không cài hay cấu hình ngầm.
- Chưa có credentials/Tunnel thực trên VPS để thử restart; chỉ kiểm thử guard và cú pháp. Cấu hình Tunnel/hostname vẫn chưa triển khai.
- Staging đạt 490 smoke checks, 9 system checks, 67 Bats tests và ShellCheck. Đã nâng VPS thử nghiệm lên `0.22.0-dev`; mã trước ở `/opt/kwvps-previous-20261021T163551Z-2Y18Xc1b`. Sau nâng: Nginx/PHP-FPM/MariaDB active, `nginx -t` đạt, HTTPS site chính trả 200. `kenhgamez.net` đã chuyển vào vùng giữ giữa hai lần quan sát; thao tác nâng cấp chỉ thay mã và không gỡ site này.

## 0.21.1-dev — xác nhận và vòng đời xóa site, 21/10/2026

- Các thao tác không xóa tại menu Sites/PHP/Nginx/SSL/DB/backup/cron và một số mục firewall, swap, Fail2ban chuyển sang xác nhận `y/N` mặc định No. Các thao tác xóa hoặc loại bỏ rule vẫn yêu cầu nhập lại đối tượng; API nội bộ vẫn kiểm tra token chính xác.
- Xóa Site hiển thị source/code, user Linux, PHP pool, Nginx, metadata, SSL/renewal và DB có metadata gắn đúng domain. Chọn (1) backup source rồi đưa site vào vùng giữ hoặc (2) không tạo backup source mới nhưng vẫn giữ bản phục hồi. Cả hai đều yêu cầu gõ lại domain. DB, chứng chỉ, user và backup độc lập không bị xóa ngầm.
- Menu Sao lưu/phục hồi có “Xóa Sạch site đã giữ” ngay dưới “Phục hồi site đã xóa”. Nó xóa vĩnh viễn **chỉ** gói site đã giữ được chọn sau khi gõ lại domain; không xóa DB, chứng chỉ, user hoặc backup độc lập. Đã thử trên `kwvps-purge.test`: tạo → đưa vào vùng giữ → xóa sạch; `nginx -t` đạt. Trên VPS có thêm site `kenhgamez.net` xuất hiện ngoài phép thử này; không sửa site đó.
- Các nhóm chưa triển khai khác vẫn cần làm; không coi bản này là production.
- Staging đạt 490 smoke checks, 9 system checks, 66 Bats tests và ShellCheck. Đã nâng VPS thử nghiệm lên `0.21.1-dev`; mã trước ở `/opt/kwvps-previous-20261021T163323Z-lNfPVEpF`. Sau nâng: Nginx/PHP-FPM/MariaDB active, `nginx -t` đạt và HTTPS site chính trả 200. `kenhgamez.net` vẫn hiện trong danh sách; không chỉnh sửa site này.

## 0.20.0-dev — Quản lý Sites, 21/10/2026

- Menu Sites có sáu mục theo thứ tự yêu cầu. Nhân bản site chọn nguồn bằng số, nhập domain đích (0 để quay lại), xác nhận `[Y/n]`; sao chép source qua bộ kiểm tra archive an toàn, tạo user/pool/vhost HTTP riêng. Không tự sao chép DB, SSL, DNS hay cron. Hỗ trợ gõ nhanh `1.4` ở menu chính.
- Xóa Site dùng xác nhận domain, backup source trước, đưa cấu hình và source vào vùng giữ root-only để có thể phục hồi. Với vhost HTTPS mẫu KwVPS, tạm giữ cả cấu hình gia hạn Certbot; không xóa chứng chỉ hoặc DB. Phân lại quyền hạn chỉ đổi owner/group source, giữ mode và lưu manifest cũ; từ chối symlink/hardlink.
- Trên VPS staging: 487 smoke checks, 9 system checks, 63 Bats tests và ShellCheck đạt. Thử clone `kwvps.kenhgamez.top` → `kwvps-clone.test`: source giống bản gốc, owner riêng, HTTP loopback 200. Đã thử phân quyền rồi xóa site clone; bản clone và backup được giữ root-only. Lần thử clone đầu phát hiện chown chạy trước khi tạo user; đã sửa và dọn đúng staging lỗi. Đường xóa HTTPS chỉ qua preflight đọc, chưa thực hiện xóa site HTTPS đang chạy. Đổi tên miền vẫn chưa triển khai.
- Đã nâng bản cài trên VPS lên `0.20.0-dev`; bản mã trước được giữ tại `/opt/kwvps-previous-20261021T153927Z-Ryf5b3HB`. Sau nâng: `kwvps --site-list` chỉ có `kwvps.kenhgamez.top`, `nginx -t` đạt, Nginx/PHP-FPM/MariaDB active, HTTPS loopback trả 200.

## 0.19.0-dev — mã cục bộ và VPS thử nghiệm, 21/10/2026

- Site mới lấy ID bằng cách viết thường domain và bỏ dấu chấm/gạch; ví dụ `kwvps.kenhgamez.top` → `kwvpskenhgameztop`. ID giới hạn 29 ký tự để user Linux `kw<ID>` không quá dài. Nếu hai domain cho cùng ID, site thứ hai bị từ chối; site hash cũ vẫn được nhận diện khi còn metadata.
- Các form tạo DB/đổi mật khẩu, tạo site, sửa pool, firewall, swap, Fail2ban và bước xác nhận cho nhập lại tại chỗ khi sai quy tắc; Enter trống hủy. Menu chọn site/DB/file/PHP cũng cho nhập lại số sai.
- Import DB quét cùng thư mục backup `/var/backups/kwvps`, lọc theo site hoặc tất cả DB. Danh sách DB/user chỉ hiện số và tên.
- Trên staging VPS đã đạt 487 smoke checks, 59 Bats tests và ShellCheck; nâng bản cài lên `0.19.0-dev`, bản trước được giữ ở `/opt/kwvps-previous-20261021T152002Z-zFY2UJDM`.
- Kết nối SSH tạm đã xác minh đúng fingerprint và tài khoản `root`. Ba site ID hash cũ trên VPS thử nghiệm được đưa vào vùng lưu giữ root-only, không xóa vĩnh viễn source/cấu hình, DB hoặc các backup cũ. Tạo lại `kwvps.kenhgamez.top` bằng ID `kwvpskenhgameztop` với PHP 8.3. Cấu hình HTTPS dùng chứng chỉ hiện hữu, cập nhật Certbot webroot sang site mới; HTTPS loopback trả 200 và `certbot renew --dry-run` thành công. `kwvps --site-list` chỉ còn site ID mới; `nginx -t` đạt.
- Lần kiểm tra HTTPS ngay sau Nginx reload ban đầu gặp độ trễ cổng 443, sau đó kiểm tra lại thành công; script di chuyển thử nghiệm được bổ sung vòng retry. Script trong `scripts/*trial*019.sh` chỉ dành đúng host thử nghiệm, không phải công cụ nâng cấp production.

## 0.18.1-dev — DB tùy đặt tên và backup cấu hình theo domain, 21/10/2026

- Menu DB có đúng 7 mục: danh sách DB, danh sách user, đổi pass, tạo DB, xóa DB, import, export. Danh sách chỉ gồm DB KwVPS quản lý, chọn bằng số. Tạo DB cho phép tên DB/user/password tự đặt, gắn với site; metadata root-only. Xóa hiển thị DB/user/site, hỏi `y/N`, tự export trước khi DROP. Import chọn `.sql`/`.sql.gz` từ `/home/db` trước, chọn DB đích sau, cảnh báo nếu đã có bảng, tự export hiện trạng và dùng user giới hạn quyền; SQL import không nguyên tử.
- Trên VPS thử nghiệm đã tạo `kwvps_trial1721`/`kwtrial1721` cho site lab, thêm một bảng, export, đổi pass, đặt dump vào `/home/db`, import và đọc lại dữ liệu đúng, rồi xóa chính xác DB thử. Bản dump upload thử đã xóa; các export và metadata cũ vẫn giữ root-only. Lần thử xóa bằng lựa chọn số bị bộ phê duyệt an toàn từ chối do thứ tự có thể đổi; sau kiểm tra danh tính DB đã dùng tên DB chính xác để dọn dữ liệu thử.
- Backup cấu hình domain chứa metadata site, PHP pool, Nginx vhost; chọn site và gói bằng số, có checksum. Restore chỉ cùng site, cùng phiên bản PHP và cùng chế độ HTTP/HTTPS; tự backup bản hiện tại, kiểm tra `php-fpm -t`, `nginx -t`, reload, health check, rollback file nếu lỗi. Đã thử site lab: pool 5→6 rồi restore backup về 5. Source, DB, SSL private key và Cloudflare không nằm trong gói cấu hình.
- Trước khi nâng `0.18.1-dev`: 474 smoke checks, 9 system checks, 54 Bats tests và ShellCheck sạch. Sau nâng: Nginx/PHP-FPM/MariaDB active, HTTPS `kwvps.kenhgamez.top` trả 200.

## 0.16.0-dev — menu và PHP theo site, 21/10/2026

- Menu con không lặp header VPS; trên terminal tương tác, màn hình được làm gọn khi chọn mục. Các thao tác chọn site, database KwVPS, backup source/DB và site đã giữ dùng danh sách đánh số; các thao tác ghi vẫn cần xác nhận domain.
- Menu PHP chọn 8.5, 8.4, 8.3, 7.4 theo số và báo bản nào đã cài. Không thêm PPA tự động. Có chỉnh `pm.max_children`/`pm.max_requests` và custom pool qua nano trên bản tạm, giữ backup và rollback nếu PHP-FPM không chấp nhận. Đường đổi PHP theo site đã viết với backup/rollback nhưng **chưa kiểm thử chuyển thực tế** vì VPS chỉ có PHP 8.3.
- Đã thử chỉnh pool `kwvps-lab.test` 5→6→5. Thử nghiệm phát hiện tên backup trùng nếu thao tác hai lần cùng giây; đã sửa dùng `BASHPID`, nâng bản lên `0.16.0-dev`. Giá trị pool về 5, Nginx/PHP-FPM active, HTTPS domain thật trả 200. Trước nâng: 451 smoke checks, 9 system checks, 47 Bats tests và ShellCheck sạch.

## 0.14.1-dev — SSL Let's Encrypt trên VPS thử nghiệm, 21/10/2026

- Domain `kwvps.kenhgamez.top` từng trỏ trực tiếp tới VPS lab. Cài Certbot từ kho Ubuntu, mở UFW 443/tcp, giữ 22/80, cấp chứng chỉ Let's Encrypt HTTP-01 không email; HTTPS trả 200, HTTP chuyển 301 sang HTTPS. Chứng chỉ hết hạn 19/01/2027; `certbot.timer` enabled, hook nạp lại Nginx sau gia hạn có quyền root. `certbot renew --dry-run --no-random-sleep-on-renew` đạt.
- Chỉ cấp cho site có vhost HTTP KwVPS nguyên bản; từ chối ghi đè vhost custom/SSL và chứng chỉ sẵn có. Sao lưu vhost trước thay, kiểm tra `nginx -t`, reload, health check HTTPS loopback và rollback vhost nếu lỗi. Vhost HTTP được cập nhật đường ACME riêng; backup bản trước nằm trong `/var/backups/kwvps`.
- Chưa có paid SSL, DNS-01, đổi ACME provider hay lệnh cấp lại chứng chỉ đã tồn tại. Bản này chỉ dành VPS thử nghiệm, không phải bản phát hành chính thức.

## 0.13.1-dev — VPS thử nghiệm, 21/10/2026

- Sửa header menu để phản ánh mọi thao tác ghi đều cần sudo/xác nhận, thay vì chỉ nhắc tạo site/backup. Bộ cài cho VPS sạch hiện bao gồm Fail2ban, UFW, cron và nano nhưng vẫn không tự bật UFW. Bộ cài mở rộng này chưa được thử lại từ VPS trắng thứ hai.
- Chạy lại 425 smoke checks, 9 system checks, 45 Bats tests và ShellCheck sạch. Nâng từ `0.13.0-dev` lên `0.13.1-dev`, giữ bản trước tại `/opt/kwvps-previous-20261021T125347Z-RHWW9u1b`. Sau nâng: `kwvps` chạy được bằng `ubuntu`, hai site còn trong registry, `nginx -t` đạt, Nginx/PHP-FPM/MariaDB/Fail2ban/cron active, UFW giữ 22/80.

## 0.13.0-dev — VPS thử nghiệm, 21/10/2026

- Thêm menu xem `/etc/crontab` và crontab root, mở root crontab bằng nano sau khi sao lưu root-only. Không tự chỉnh `/etc/cron.d`; `crontab -e` kiểm tra cú pháp khi lưu. Đã thử đọc cron trên VPS; root chưa có crontab riêng, cron service active. Chưa thử lưu lịch qua nano trong phiên tương tác.
- Trước nâng cấp: 425 smoke checks, 9 system checks, 45 Bats tests và ShellCheck sạch. Nâng từ `0.12.0-dev` lên `0.13.0-dev`; bản trước ở `/opt/kwvps-previous-20261021T125016Z-XP1LoxxM`. Sau nâng: `kwvps` bằng user `ubuntu`, hai site trong registry, `nginx -t` đạt, Nginx/PHP-FPM/MariaDB/Fail2ban/cron active, UFW active với 22/80.

## 0.12.0-dev — VPS thử nghiệm, 21/10/2026

- Thêm phục hồi vhost HTTP nguyên bản theo site KwVPS và baseline Nginx toàn cục tối thiểu. Chỉ sửa file sở hữu KwVPS, từ chối vhost chứa SSL, sao lưu file cũ, kiểm tra `nginx -t` và reload, cố gắng rollback nếu lỗi.
- Trên VPS thử nghiệm đã áp baseline (`server_tokens off`, `client_max_body_size 32m`), thêm comment thử vô hại vào vhost `kwvps-lab.test` rồi phục hồi về mẫu. Bản trước phục hồi được giữ ở `/var/backups/kwvps/nginx-site-89350b430479-20261021T124627Z-36618.conf`. Sau đó `nginx -t` đạt, HTTP 200; header Server không lộ số version.
- Trước nâng cấp: 423 smoke checks, 9 system checks, 43 Bats tests và ShellCheck sạch. Nâng từ `0.11.0-dev` lên `0.12.0-dev`, bản trước ở `/opt/kwvps-previous-20261021T124640Z-f7f0l6Fz`. Hai site còn trong registry, các service chính active.

## 0.11.0-dev — VPS thử nghiệm, 21/10/2026

- Thêm quản lý swapfile riêng: kích thước 128-8192 MB, kiểm tra dung lượng trống + 512 MB dự phòng, khóa thao tác, xác nhận chính xác, kiểm tra chủ sở hữu/quyền và sao lưu `/etc/fstab` trước khi sửa. Không thay swap khác.
- VPS thử nghiệm: thêm swapfile 128 MB, thấy `swapon --show`, sau đó gỡ bằng KwVPS. Sau thử `swapon --show` rỗng như ban đầu; hai bản fstab trước thay đổi giữ root-only tại `/var/backups/kwvps`. File swap tạm đã xóa, không thể khôi phục nội dung swap; không chứa dữ liệu ứng dụng cần giữ.
- Trước nâng cấp: 419 smoke checks, 9 system checks, 41 Bats tests và ShellCheck sạch. Nâng từ `0.10.0-dev` lên `0.11.0-dev`; bản trước ở `/opt/kwvps-previous-20261021T124138Z-YltEztvS`. Sau nâng: `kwvps` dùng được bằng user `ubuntu`, hai site còn trong registry, UFW active với 22/80, `nginx -t` đạt và Nginx/PHP-FPM/MariaDB/Fail2ban active.

## 0.10.0-dev — VPS thử nghiệm, 21/10/2026

- Triển khai menu UFW: xem rule/IP, mở/đóng port TCP/UDP và ban/unban IPv4, xác nhận chính xác trước ghi. Chỉ gỡ rule có nhãn KwVPS; không tự bật UFW, từ chối mở công khai 3306, từ chối đóng 22 hoặc port SSH cấu hình, từ chối ban IP đang có phiên SSH.
- VPS thử nghiệm: mở trước `22/tcp` và `80/tcp`, bật UFW rồi xác minh SSH còn kết nối. Dùng mã staging mở/đóng `8081/tcp` và ban/unban `203.0.113.48` thành công; các rule thử đã gỡ. UFW sau thử chỉ còn 22/80 IPv4+IPv6. Không tác động firewall nhà cung cấp.
- Trước nâng cấp: 413 smoke checks, 9 system checks, 39 Bats tests và ShellCheck sạch. Nâng từ `0.9.0-dev` lên `0.10.0-dev`; bản cũ ở `/opt/kwvps-previous-20261021T123626Z-jKGDR5Ob`. Sau nâng: `ubuntu` chạy được `kwvps`, hai site còn trong registry, `nginx -t` đạt, Nginx/PHP-FPM/MariaDB/Fail2ban active, site mẫu HTTP 200.

## 0.9.0-dev — VPS thử nghiệm, 21/10/2026

- Thêm hướng dẫn truy cập DB từ xa qua SSH tunnel trong menu; không thay cấu hình MariaDB/UFW, không mở 3306 ra Internet. Đã thử kế hoạch thực tế cho `kwvps-delete.test`; tên DB/user đúng metadata và không in mật khẩu.
- Thêm xem IP bị khóa, ban/unban IPv4 theo jail Fail2ban hiện hữu. Kiểm tra tên jail/IP/xác nhận, từ chối ban IP của phiên SSH đang đăng nhập. Cài Fail2ban từ kho Ubuntu trên VPS thử nghiệm; service active, jail `sshd` hoạt động. Đã ban rồi unban `203.0.113.47`; sau đó IP thử không còn trong danh sách ban. Không chỉnh hoặc gỡ ban IP khác đã tồn tại.
- Trước nâng cấp: 405 smoke checks, 9 system checks, 36 Bats tests và ShellCheck sạch trên VPS. Nâng từ `0.8.1-dev` lên `0.9.0-dev`, giữ bản cũ tại `/opt/kwvps-previous-20261021T122946Z-KzOXwaPf`. Sau nâng: `ubuntu` chạy được `kwvps --version`, hai site còn trong registry, `nginx -t` đạt, Nginx/PHP-FPM/MariaDB active, MariaDB vẫn chỉ nghe `127.0.0.1:3306`, site mẫu HTTP 200.
- Chưa có truy cập MariaDB trực tiếp từ Internet; đây là quyết định an toàn mặc định. Firewall menu và nhiều nhóm chức năng khác vẫn chưa triển khai.

## 0.8.1-dev — VPS thử nghiệm, 21/10/2026

- Sửa import DB dùng tài khoản DB riêng giới hạn trong site, không chạy SQL từ archive bằng root. Đã thử import thành công trên VPS và xác minh dữ liệu mẫu. Sau nâng cấp, lệnh `kwvps` chạy được bằng user `ubuntu`.

## 0.8.0-dev — VPS thử nghiệm, 21/10/2026

- Nhóm MariaDB cho site KwVPS: liệt kê metadata, tạo DB/user riêng chỉ tại `localhost`, export gzip kèm SHA-256, import từ backup thuộc đúng site và xóa DB sau khi tự export. Mật khẩu ngẫu nhiên lưu `/etc/kwvps/db/` quyền root-only; không in ra menu/chat. Import chưa nguyên tử và có thể để DB ở trạng thái một phần nếu SQL lỗi.
- Đã cài MariaDB từ kho Ubuntu trên VPS thử nghiệm; cổng 3306 chỉ lắng nghe `127.0.0.1`. Tạo DB cho `kwvps-delete.test`, xác minh user riêng đăng nhập được, export/checksum đạt, import đưa giá trị thử về đúng bản trước, xóa có export trước rồi tạo lại và import thành công. DB thử hiện có bảng `kwvps_probe` với giá trị `ok`.
- Trước nâng cấp: 397 smoke checks, 9 system checks, 32 Bats tests và ShellCheck đạt. Đã nâng VPS từ `0.7.0-dev` lên `0.8.0-dev`; bản trước ở `/opt/kwvps-previous-20261021T121738Z-24tT5E5F`. Nginx, PHP-FPM, MariaDB đều active.
- Bộ cài mới sẽ cài MariaDB cùng Nginx/PHP-FPM trên VPS sạch; chưa thử lại toàn bộ bộ cài từ VPS mới. Chưa có remote DB hay backup full domain.

## 0.7.0-dev — VPS thử nghiệm, 21/10/2026

- Thêm tạo, liệt kê và export DB theo site; gói export root-only, có checksum và không chứa mật khẩu kết nối. VPS thử nghiệm đã nâng từ `0.6.2-dev`, bản trước ở `/opt/kwvps-previous-20261021T121416Z-2KPWT3gj`.

## 0.6.2-dev — VPS thử nghiệm, 21/10/2026

- Sửa lỗi bộ nâng cấp giữ quyền `0700` của thư mục staging khi chuyển thành `/opt/kwvps`, khiến lệnh `kwvps` bị từ chối với user thường. Đã xác minh quyền của `/opt/kwvps`, sửa thành `0755` trên VPS thử nghiệm; bộ nâng cấp mới đặt quyền `0755` và thử lệnh bằng user `nobody` trước/sau chuyển.
- Nâng từ `0.6.1-dev` lên `0.6.2-dev` bằng bộ nâng cấp đã sửa. Bản trước ở `/opt/kwvps-previous-20261021T113746Z-CDSePSmd`. Sau nâng cấp, tài khoản `ubuntu` chạy được `kwvps --version` và `kwvps --site-list`; hai site vẫn được liệt kê. Trước nâng cấp, 396 smoke checks, 9 system checks, 26 Bats tests và ShellCheck đạt.

## 0.6.1-dev — VPS thử nghiệm, 21/10/2026

- Thêm menu liệt kê và phục hồi site đã đưa vào vùng giữ. Kiểm tra domain/site ID, metadata, cấu hình nguyên bản, quyền vùng giữ và xung đột đích trước khi chuyển các đường dẫn về; kiểm tra Nginx/PHP-FPM rồi reload, cố gắng rollback nếu lỗi.
- Trên VPS: 396 smoke checks, 9 system checks, 26 Bats tests và ShellCheck đạt. Phục hồi `kwvps-delete.test` từ vùng giữ thành công; cả site này và `kwvps-lab.test` đều HTTP 200. Đã nâng bản cài từ `0.6.0-dev` lên `0.6.1-dev`; bản trước ở `/opt/kwvps-previous-20261021T113434Z-fPk5g3Sx`.
- Chưa thử fault injection từng bước rollback hoặc tính nhất quán ứng dụng có DB; vùng giữ rỗng sau khi phục hồi vẫn còn để kiểm tra thủ công.

## 0.6.0-dev — VPS thử nghiệm, 21/10/2026

- Thêm menu **Đưa site ra khỏi phục vụ** cho site HTTP nguyên bản do KwVPS tạo. Thao tác đòi nhập lại domain, từ chối vhost/pool đã tùy chỉnh, sao lưu source trước rồi chuyển cấu hình và toàn bộ thư mục site vào `/var/backups/kwvps/retired/` quyền root-only. Không xóa vĩnh viễn user, log, backup hoặc DB. Khi lỗi cấu hình/reload, script cố gắng trả các đường dẫn cũ về.
- Trên VPS: 393 smoke checks, 9 system checks, 25 Bats tests và ShellCheck đạt. Tạo site riêng `kwvps-delete.test` → HTTP 200 → đưa ra khỏi phục vụ thành công. Danh sách site chỉ còn `kwvps-lab.test`; `nginx -t` đạt, Nginx/PHP-FPM active, site mẫu vẫn HTTP 200. Đã nâng `0.5.1-dev` lên `0.6.0-dev`; bản trước ở `/opt/kwvps-previous-20261021T113039Z-x0afcQMY`.
- Chưa có menu phục hồi site từ vùng giữ hoặc xóa vĩnh viễn; user hệ thống của site đã gỡ vẫn còn nên chưa thể tạo lại cùng domain bằng menu hiện tại. Chưa thử fault injection cho từng bước rollback.

## 0.5.1-dev — VPS thử nghiệm, 21/10/2026

- Backup source giờ kiểm tra trước rằng gói tạo ra có thể được bộ restore an toàn chấp nhận; source chứa symlink/hardlink/entry đặc biệt bị từ chối thay vì tạo một backup không thể restore bằng KwVPS. Header menu cũng ghi đúng các thao tác ghi hiện có.
- Trên VPS thử nghiệm: 393 smoke checks, 9 system checks, 23 Bats tests và ShellCheck đạt. Đã nâng từ `0.5.0-dev` lên `0.5.1-dev`, giữ bản trước tại `/opt/kwvps-previous-20261021T112557Z-KLZOX6EK`. Backup mới từ site mẫu đạt; Nginx/PHP-FPM active và site trả HTTP 200.

## 0.5.0-dev — VPS thử nghiệm, 21/10/2026

- Thêm restore **chỉ source** cho site KwVPS: xác minh checksum và site ID; bộ giải nén từ chối symlink, hardlink, thiết bị, đường dẫn thoát ngoài và giới hạn số file/dung lượng. Tạo backup hiện trạng trước khi thay, giữ nguyên thư mục source cũ để quay lại. Không sửa DB/SSL/cấu hình web.
- Kiểm thử staging trên VPS Ubuntu 24.04.4: 393 smoke checks, 9 system checks, 22 Bats tests và ShellCheck đạt. Restore từ backup của `kwvps-lab.test` thành công; trước đó tạo thêm backup hiện trạng. Quyền source sau restore là user site/`www-data`, `0750` cho thư mục, `0640` cho file; `nginx -t` đạt, Nginx/PHP-FPM active và HTTP loopback trả `200`.
- Đã nâng VPS từ `0.4.0-dev` lên `0.5.0-dev`; bản trước giữ tại `/opt/kwvps-previous-20261021T112250Z-7A86S4im`.
- Chưa có restore full cấu hình/domain hoặc DB. Restore source trên site động có thể cần bảo trì ứng dụng và đối chiếu DB riêng; chưa chứng minh tính nhất quán khi đang ghi dữ liệu.

## 0.4.0-dev — VPS thử nghiệm, 21/10/2026

- Thêm mục chỉ đọc xem PHP-FPM pool theo site và journal PHP-FPM đúng phiên bản site; journal vẫn dùng chung giữa các site cùng PHP version, không phải log riêng của ứng dụng.
- Trước nâng cấp: 392 smoke checks, 9 system checks, 20 Bats tests và ShellCheck đạt trên VPS Ubuntu 24.04.4.
- Đã nâng VPS thử nghiệm từ `0.3.0-dev` lên `0.4.0-dev`. Bản trước giữ tại `/opt/kwvps-previous-20261021T111706Z-fegdhnjr`. Sau nâng cấp, pool site mẫu hiển thị đúng PHP 8.3/user/socket; đọc journal thành công, `nginx -t` đạt, Nginx/PHP-FPM active, HTTP loopback trả `200`.
- Chưa có thao tác đổi PHP version, chỉnh pool hoặc log PHP ứng dụng theo domain.

## 0.3.0-dev — mã cục bộ, 21/10/2026

- Thêm sao lưu riêng source của site KwVPS: xem kế hoạch, nhập lại domain, khóa thao tác site, archive tạm, kiểm tra tar, checksum SHA-256, lưu trong thư mục root-only. Có mục liệt kê và xác minh gói backup; không bao gồm DB/SSL/cấu hình và chưa hỗ trợ restore.
- Kiểm thử cục bộ sau thay đổi: 392 smoke checks, 9 system checks đạt. Trên VPS thử nghiệm: 19 Bats tests và ShellCheck đạt, không còn cảnh báo.
- Đã thử trực tiếp mã staging trên VPS Ubuntu 24.04.4: tạo backup source cho `kwvps-lab.test`, xác minh SHA-256 và cấu trúc tar thành công. Gói chỉ chứa `public/index.html`, lưu dưới `/var/backups/kwvps` với thư mục `0700`, hai file archive/checksum `0600`, sở hữu `root:root`. Sau thao tác, `nginx -t` đạt, Nginx/PHP 8.3 FPM vẫn active và HTTP loopback của site trả `200`. Chưa thử restore hay tính nhất quán khi site đang ghi dữ liệu.
- Đã thêm `upgrade.sh --check/--apply` cho bản cài thử nghiệm: kiểm tra hệ điều hành, marker cài đặt, quyền sở hữu và Nginx; dựng mã mới ở thư mục riêng, kiểm tra doctor/site-list, chuyển sang bản mới và giữ nguyên bản cũ tại `/opt/kwvps-previous-*`. Nếu kiểm tra sau khi chuyển thất bại, script cố gắng trả mã cũ về; không sửa site, database hoặc service. Đây chưa phải cơ chế phát hành/rollback production.
- Đã nâng VPS thử nghiệm từ `0.2.0-dev` lên `0.3.0-dev` bằng đường nâng cấp này. Bản cũ ở `/opt/kwvps-previous-20261021T111417Z-cZAOTxQF`. Trước nâng cấp, staging đạt 392 smoke checks, 9 system checks, 19 Bats tests và ShellCheck sạch. Sau nâng cấp, lệnh `kwvps --version`, danh sách site và mục danh sách backup trong menu hoạt động; `nginx -t` đạt, Nginx/PHP-FPM active, site mẫu trả HTTP 200. Không chạy lại `install.sh --apply`.
- Chức năng xóa site vẫn chưa có; không dùng backup source như bằng chứng đã có khả năng khôi phục đầy đủ.

## 0.2.0-dev — 21/10/2026

- Đã sửa đường mở preview tiếng Việt trên Windows và có hướng dẫn riêng.
- Có bộ cài cục bộ `install.sh --check/--apply` cho VPS Ubuntu 24.04 sạch. Chưa có GitHub release hoặc lệnh cài từ GitHub.
- Có registry site, kế hoạch tạo site, tạo domain HTTP với user và PHP-FPM pool riêng, Nginx vhost, kiểm tra cấu hình, reload và health check. Các thao tác tạo chỉ chạy trên VPS đã cài KwVPS và cần xác nhận domain.
- Có mục đọc dung lượng, tìm file lớn và xem log Nginx theo domain do KwVPS quản lý.
- Kiểm thử Git Bash trên Windows: 381 kiểm tra smoke và 9 kiểm tra hệ thống đạt; Bash syntax đạt. Chưa có ShellCheck/Bats trên máy hiện tại.
- Người dùng đã thử trên VPS Ubuntu 24.04.4 LTS `x86_64` riêng: bộ cài báo đã cài, `kwvps --doctor` đạt, `nginx -t` thành công, Nginx và PHP 8.3 FPM đều active. Site `kwvps-lab.test` xuất hiện trong registry; truy vấn loopback theo Host trả `HTTP 200` với trang chào KwVPS. Probe PHP tạm qua cùng vhost trả `HTTP 200` và nội dung `fpm-fcgi`, xác nhận request PHP đến PHP-FPM. Đây là kết quả do người dùng cung cấp, chưa phải kiểm thử tự động hoặc rà soát toàn bộ trạng thái VPS.
- Chưa kiểm chứng cách ly giữa nhiều site, đường lỗi/rollback, DNS/SSL hoặc độ bền sau reboot. Bộ tạo site chưa đủ điều kiện production; chức năng xóa site cũng chưa có.

Tiếp theo: hoàn thiện đường xóa/khôi phục và kiểm thử lỗi thực tế, rồi triển khai SSL, DB và backup trước khi dùng website có dữ liệu.

## 0.1.0-dev — 21/10/2026

Đã chuyển chat vào Project `KwVPS Script`, thư mục `D:\KwVPS Script`.

Đã triển khai bản nền tảng chỉ đọc theo README. Chưa có bộ cài, GitHub repository, hoặc thao tác quản trị ghi dữ liệu.

### Kiểm thử

- Kiểm tra cú pháp và smoke test bằng Git Bash 5.2 trên Windows.
- Có Bats suite và GitHub Actions cho Ubuntu 24.04.
- Máy hiện tại chưa tìm thấy ShellCheck/Bats trong Git Bash, WSL không liệt kê distro. Chưa chạy Bats/ShellCheck hoặc kiểm thử VPS Ubuntu; không được xem đây là bản sẵn sàng production.
- Bộ test bao gồm domain/port không hợp lệ, shell injection, parser os-release không thực thi mã, RAM theo available, catalog, điều hướng, EOF và tùy chọn CLI sai.

### Tiếp theo

1. Cài công cụ kiểm thử được cho phép hoặc chạy workflow trên repository người dùng chọn.
2. Registry site có schema và kiểm tra đường dẫn, user/pool mapping.
3. Cơ chế backup/atomic config/validation/lock trước thao tác ghi.
4. Module Sites + PHP-FPM + Nginx, sau đó DB/SSL và các module còn lại theo đặc tả.

Không kết nối hoặc thay đổi VPS LarVPS production. Tài liệu đặc tả vẫn là mục tiêu cuối, không phải danh sách tính năng đã hoàn thành.
