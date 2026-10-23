# Thử KwVPS trên VPS Ubuntu 24.04 riêng

Bản phát triển đã qua các phép thử HTTP/PHP-FPM, SSL Let's Encrypt, backup source và MariaDB cơ bản trên Ubuntu 24.04.4 LTS; chưa kiểm thử đầy đủ các đường lỗi. Chỉ dùng VPS thử nghiệm mới, có snapshot và console cứu hộ. VPS LarVPS có website thật không thuộc phạm vi thử nghiệm.

## Trên máy tính

Để xem menu tiếng Việt trong PowerShell, chạy `./scripts/preview-utf8.ps1` tại thư mục dự án. Xem [hướng dẫn terminal](TIENG-VIET-TERMINAL.md).

Kiểm tra kế hoạch site trên Git Bash:

```bash
bash kwvps --site-plan example.com 8.3
```

Lệnh này không thay đổi máy. Hãy thay `example.com` bằng domain thử nghiệm do bạn kiểm soát.

## Đưa mã lên VPS thử nghiệm

Chuyển toàn bộ thư mục dự án qua Git/SFTP/SCP vào thư mục riêng trên VPS. Không chuyển file bí mật, backup hoặc private key. Chưa có GitHub repository nên chưa có một lệnh cài từ GitHub đáng tin cậy để công bố.

Trong thư mục đã chuyển trên VPS:

```bash
bash install.sh --check
```

Bộ cài dừng nếu không phải Ubuntu 24.04, thiếu systemd hoặc thấy web stack/control panel hiện có. Nếu kết quả đạt và snapshot sẵn sàng:

```bash
sudo bash install.sh --apply
kwvps --doctor
kwvps --site-plan example.com 8.3
sudo kwvps
```

Trong menu chính chọn `1. Quản lý site` → `2. Thêm domain/subdomain`, nhập domain và PHP `8.3`, đọc kế hoạch rồi nhập lại domain để xác nhận. Bộ cài không mở firewall; site tạo ra chỉ nghe HTTP 80 trên Nginx. DNS, SSL, database và ứng dụng chưa được cấu hình.

Để xem site sau khi tạo:

```bash
kwvps --site-list
```

Thử từ VPS bằng `curl` với Host của domain để xác nhận trang chào, rồi thử qua DNS nếu đã trỏ đúng. Nếu Nginx/PHP-FPM báo lỗi trong khi tạo, ghi lại thông báo và kiểm tra dữ liệu còn sót lại trước khi chạy lại; rollback cố gắng gỡ các file mới do lần tạo đó sinh ra, nhưng không hứa khôi phục mọi trạng thái của hệ thống.

`kwvps-lab.test` đã được tạo trên VPS thử nghiệm; trang chào trả HTTP 200 qua loopback, và probe PHP tạm trả `fpm-fcgi` qua cùng vhost. Bản này **chưa có mục xóa site**: đừng tạo nhiều site thử nếu chưa có kế hoạch giữ lại hoặc khôi phục snapshot.

Mã `0.18.1-dev` đã cài trên VPS thử nghiệm. Menu `kwvps` có sao lưu/khôi phục source và cấu hình domain, danh sách/kiểm tra backup, xem PHP-FPM pool và journal theo site. Để thử restore source, chọn **Sao lưu/phục hồi → Restore source/code**, chọn site và backup theo số thứ tự, đọc kế hoạch rồi nhập lại domain xác nhận. Backup source không gồm database, SSL hay cấu hình web server; đừng coi đây là khôi phục website đầy đủ.

## DB và backup cấu hình

Menu **Quản lý DB** gồm 7 mục. `Tạo DB` yêu cầu chọn site bằng số rồi nhập tên DB, user và mật khẩu. Ký tự mật khẩu hiện trong terminal khi nhập để bạn kiểm tra; KwVPS không in lại mật khẩu sau đó. Chỉ nhập khi màn hình PuTTY không bị chia sẻ hoặc ghi hình. `Import DB` tìm file `.sql`/`.sql.gz` trong `/var/backups/kwvps`, cùng nơi lưu backup/export; chọn file bằng số trước rồi chọn DB đích bằng số. Nếu DB có bảng, menu cảnh báo trước khi xác nhận tên DB. `Export DB` và `Xóa DB` đều chọn theo tên DB hiện trong danh sách; xóa hiển thị DB/user/site và hỏi `y/N`. Export DB mới tạo một file `db-<tên-DB>-YYYYMMDD-HHMMSS[-N].sql.gz`, không kèm `.sha256`; backup cũ không bị xóa. Import **không tự export DB đích** và không thể tự rollback SQL: hãy chọn Export DB thủ công trước nếu cần giữ hiện trạng, sau đó kiểm tra dữ liệu/ứng dụng. Xóa DB vẫn tự export trước khi xóa. File dump tải lên thư mục này cần do root quản lý, không mở quyền ghi cho user web.

Menu **Sao lưu/phục hồi** liệt kê backup source/code và backup cấu hình domain theo số, kèm site nếu còn trong registry. File mới có tên `source-<domain>-YYYYMMDD-HHMMSS[-N].tar.gz` hoặc `config-<domain>-YYYYMMDD-HHMMSS[-N].tar.gz`; domain quá dài dùng site ID. Hai loại archive vẫn có `.sha256`; bản cấu hình có token Cloudflare còn có file `.cf.enc` mã hóa và checksum riêng. Giữ toàn bộ file liên quan khi chuyển máy; archive tên cũ vẫn phục hồi được. Backup cấu hình gồm site metadata, PHP pool và Nginx vhost; không gồm source, DB hoặc SSL private key. Restore cấu hình chỉ cùng site/PHP/chế độ HTTP-HTTPS. Đã thử backup/restore trên `kwvps-lab.test` với `pm.max_children` 5→6→5; bản trước restore được giữ trong `/var/backups/kwvps` quyền root-only.

## Menu và PHP theo site

Menu chính hiển thị header VPS một lần; menu con không lặp header. Trên terminal tương tác, chọn mục sẽ chuyển sang màn hình gọn của mục đó. Những thao tác site/DB/backup hiện liệt kê mục đánh số để chọn thay vì buộc gõ tên; thao tác ghi vẫn cần nhập lại domain để xác nhận.

**Quản lý PHP** hiển thị bốn lựa chọn theo thứ tự 8.5, 8.4, 8.3, 7.4 và ghi rõ bản nào đã cài/đạt bản vá. Mục **Cài gói PHP-FPM** chỉ thêm PPA Ubuntu `ppa:ondrej/php` sau xác nhận `y/N`; xem candidate, nguồn và mô phỏng APT trước khi cài. PHP 7.4 có thể cài từ PPA rồi chọn khi tạo, clone, đổi tên hoặc chuyển site; mỗi thao tác yêu cầu xác nhận cảnh báo EOL. KwVPS không xác minh PHP 7.4 an toàn, chỉ cân nhắc cho ứng dụng cũ và không khuyến nghị website Internet. Trên VPS lab đã cài 8.4.27 và 8.5.12 từ PPA, cùng `php-common` dùng chung; mặc định `php` CLI chuyển sang 8.5, còn FPM/site 8.3 giữ nguyên. Đã tạo site `.test` bằng PHP 8.4, chuyển sang 8.5, kiểm HTTP 200 rồi xóa sạch site thử. Custom pool qua nano có backup/test/rollback nhưng chưa thử phiên nano tương tác.

## SSL thử nghiệm

`kwvps.kenhgamez.top` đã được cấp Let's Encrypt HTTP-01; DNS từng trỏ trực tiếp tới VPS lab, UFW mở 80/443, HTTP chuyển HTTPS và HTTPS trả 200. Chứng chỉ hết hạn 19/01/2027. Certbot timer và hook reload Nginx đã bật; dry-run gia hạn đạt. Không đăng ký email nên **không có cảnh báo hết hạn qua email**. Kiểm tra tại menu **Quản lý SSL → Xem SSL**; chạy `sudo kwvps` để xem ngày hết hạn (user thường chỉ thấy trạng thái HTTPS). Mục **Domain không SSL** chỉ liệt kê site KwVPS còn HTTP. Muốn cấp cho site khác, cần DNS công khai trỏ về VPS, cổng 80/443 mở và vhost HTTP nguyên bản; chọn **Cấp Let's Encrypt** rồi nhập lại domain xác nhận. Không lặp lại lệnh cấp nhiều lần khi CA báo lỗi/rate limit.

Menu **Quản lý DB** hiện có liệt kê, tạo, export, import từ backup và xóa DB cho site đã quản lý. Các thao tác cần `sudo kwvps`; mật khẩu kết nối nằm trong metadata root-only. Import không tự export hiện trạng và không nguyên tử: nếu SQL lỗi, cần kiểm tra DB và dùng bản Export DB bạn đã chủ động tạo trước đó (nếu có) để phục hồi. MariaDB thử nghiệm chỉ nghe cổng 3306 trên loopback.

Mục **Remote database qua SSH tunnel** chỉ in hướng dẫn kết nối an toàn theo domain và cổng cục bộ; nó không mở MariaDB ra Internet hay đổi firewall. Mở tunnel trên máy tính của bạn, dùng DB/user ở màn hình và tự đọc mật khẩu từ metadata root-only trên VPS.

Menu **Fail2ban** xem jail và IP bị khóa, ban/unban IPv4 trong jail đang có. Bản 0.9.0-dev đã thử ban rồi unban địa chỉ thử `203.0.113.47` trong jail `sshd`; địa chỉ này không còn trong danh sách ban. Không thử ban IP kết nối của mình; chức năng chặn IP đang có phiên SSH hoạt động. Nếu jail chưa có, cấu hình Fail2ban riêng trước khi dùng menu này.

Menu **Firewall** chỉ thay rule UFW khi UFW đã active; KwVPS không tự bật để tránh khóa SSH. VPS thử nghiệm đã được mở sẵn `22/tcp` và `80/tcp` rồi bật UFW, kiểm tra SSH vẫn vào được. Đã thử KwVPS mở/đóng `8081/tcp` và ban/unban IPv4 thử `203.0.113.48`; sau thử chỉ còn rule 22/80 (IPv4 và IPv6). Khóa port chỉ gỡ rule mang nhãn KwVPS, không gỡ rule do quản trị viên tạo. UFW không đại diện cho firewall của nhà cung cấp VPS.

Menu **Swap** chỉ quản lý `/var/lib/kwvps/swapfile`, giữ bản sao `/etc/fstab` trước thay đổi. Trên VPS thử nghiệm đã thêm 128 MB rồi gỡ; VPS trở về trạng thái không có swap. Hai bản fstab trước thay đổi vẫn nằm trong `/var/backups/kwvps` quyền root-only. Gỡ swapfile là thao tác xóa file, nhưng bản fstab được lưu; dữ liệu swap tạm không phải dữ liệu ứng dụng có thể khôi phục.

Menu **Nginx** có phục hồi vhost HTTP KwVPS và áp baseline global tối thiểu. Đã áp baseline trên VPS thử nghiệm, thêm một comment thử vào vhost `kwvps-lab.test` rồi phục hồi về mẫu; bản vhost trước phục hồi nằm ở `/var/backups/kwvps/nginx-site-89350b430479-20261021T124627Z-36618.conf`. `nginx -t` đạt, site trả HTTP 200. Phục hồi sẽ từ chối vhost có SSL để không làm mất cấu hình chứng chỉ. Baseline ảnh hưởng mọi site Nginx trên cùng máy, nên không dùng tùy tiện trên VPS có website khác.

Menu **Cron** xem `/etc/crontab` và crontab root. Mục nano sao lưu crontab root vào `/var/backups/kwvps` trước khi mở trình sửa; `crontab -e` sẽ kiểm tra cú pháp lúc lưu. Trên VPS đã thử phần xem và xác minh dịch vụ cron active; chưa thử lưu một lịch mới qua nano, nên cần kiểm tra tương tác trực tiếp trước khi dùng cho tác vụ quan trọng.

Menu **Quản lý site → Đưa site ra khỏi phục vụ** chỉ nhận site HTTP có cấu hình pool/vhost nguyên bản. Nó sao lưu source rồi giữ tài nguyên dưới `/var/backups/kwvps/retired/`, không xóa vĩnh viễn. Menu **Phục hồi site đã giữ** liệt kê tên vùng giữ và đưa cấu hình/source trở lại nếu không có xung đột. Domain thử `kwvps-delete.test` đã qua chu trình tạo → đưa ra khỏi phục vụ → phục hồi; sau đó cả nó và `kwvps-lab.test` đã được lưu giữ trong lần chuyển ID 0.19.0-dev. Hiện chỉ còn `kwvps.kenhgamez.top` trong danh sách site đang hoạt động.

Khi có bản mã mới, dùng `sudo bash upgrade.sh --check` từ thư mục mã đã chuyển lên VPS rồi mới dùng `sudo bash upgrade.sh --apply --confirm=UPGRADE-KWVPS`. Script giữ bản mã cũ ở `/opt/kwvps-previous-*` và không sửa dữ liệu site. Đường nâng cấp này chỉ dành cho VPS thử nghiệm; không chạy `install.sh --apply` lại trên VPS đã cài.

### Kiểm tra PHP trên site thử nghiệm đã tạo

Chỉ chạy trên VPS thử nghiệm có site `kwvps-lab.test` với ID `89350b430479`. Phép thử tạo file PHP tên ngẫu nhiên, không ghi đè file sẵn có; subshell tự gỡ file khi kết thúc, kể cả khi `curl` báo lỗi. Nội dung trả về phải là `fpm-fcgi` nếu PHP-FPM xử lý request:

```bash
(
  set -Eeuo pipefail
  probe=$(sudo mktemp --suffix=.php /var/www/kwvps/89350b430479/public/kwvps-probe-XXXXXXXX)
  trap 'sudo rm -f -- "$probe"' EXIT
  printf '%s\n' '<?php echo PHP_SAPI;' | sudo tee "$probe" >/dev/null
  sudo chmod 0644 "$probe"
  curl --noproxy '*' -i -H 'Host: kwvps-lab.test' "http://127.0.0.1/$(basename "$probe")"
  printf '\n'
)
```

Không dùng `phpinfo()` làm trang test vì có thể lộ chi tiết cấu hình. Nếu kết quả không phải `fpm-fcgi`, ghi lại phản hồi và log lỗi để điều tra; không coi HTTP 200 của trang HTML là PHP đã đạt.

## Kiểm tra trước khi báo hoàn tất

Chạy `bash tests/smoke.sh` và `bash tests/system-smoke.sh` trên VPS thử nghiệm. Sau đó cần thử tạo hai domain, xem mỗi site có PHP pool/user riêng, kiểm tra trang HTTP và các đường lỗi ở bước `nginx -t`, `php-fpm<version> -t`, restart, xác nhận service active và health check site. ShellCheck/Bats trong workflow GitHub hiện chưa chạy do chưa có repository. Chưa dùng bản này cho website thật.
