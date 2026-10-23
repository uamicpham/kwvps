# KwVPS

Dự án script quản lý VPS cho **Ubuntu Server 24.04 LTS sạch, x86_64 và systemd**.

Sau khi cài, lệnh mở menu là `kwvps`.

## Trạng thái

Phiên bản `0.50.6` dùng API token Cloudflare riêng theo site; backup cấu hình domain có thể kèm token mã hóa bằng mật khẩu. Xem [ghi chú phát hành 0.50.6](docs/RELEASE-NOTES-0.50.6.md), [bảng trạng thái](docs/TRANG-THAI-CHUC-NANG.md) và [lịch sử release](https://github.com/uamicpham/kwvps/releases). Bản công khai mới nhất chỉ thay đổi sau khi GitHub Release xuất bản thành công.

Quản lý Sites có tạo, đổi tên miền HTTP nguyên bản, clone source/code, xóa với hai lựa chọn giữ vùng phục hồi/xóa sạch và phân lại quyền. Menu Backup có phục hồi hoặc xóa sạch gói site đã giữ. Tunnel/route thật đã được thử trên VPS lab; đổi tên site không tự cập nhật DNS/route Cloudflare hoặc URL ứng dụng. Các thao tác không xóa dùng xác nhận `y/N`; xóa yêu cầu gõ lại đối tượng. **Không cài đè lên VPS LarVPS, web stack có sẵn hoặc máy chứa website/dữ liệu.**

## Cài bằng một dòng trên VPS mới

Chỉ chạy trên **Ubuntu Server 24.04 LTS sạch, x86_64, systemd**, có `curl`, `python3`, `tar`, `sha256sum` và quyền `sudo`/root. Không chạy trên VPS đã có website, LarVPS hay web stack khác. Bộ cài yêu cầu nhập `INSTALL KWVPS` trước khi cài package.

```bash
set -o pipefail; curl -fsSL https://raw.githubusercontent.com/uamicpham/kwvps/main/scripts/bootstrap-release.sh | sudo bash -s -- --apply
```

Lệnh này không cần đổi khi có release mới: nó tải bootstrap hiện tại từ `main`, rồi chọn **release mới nhất** trên GitHub. `pipefail` giúp lệnh báo lỗi nếu tải bootstrap thất bại. Bootstrap kiểm tra SHA-256 của gói release trước khi cài. Tuy nhiên, nhánh `main` có thể thay đổi và cách `curl | bash` không kiểm tra riêng checksum của bootstrap; chỉ chạy khi bạn tin tưởng repository. Nếu muốn ghim cả phiên bản và kiểm tra bootstrap trước khi chạy, dùng lệnh bên dưới.

```bash
kwvps_tmp=''; kwvps_tmp=$(mktemp) && curl -fsSL --proto '=https' --tlsv1.2 'https://raw.githubusercontent.com/uamicpham/kwvps/v0.50.1/scripts/bootstrap-release.sh' -o "$kwvps_tmp" && printf '%s  %s\n' '8873fd8d6ae9c6b9207b8b2ebe2401b6b42d3bc3bf6d59f1548564f817e359f1' "$kwvps_tmp" | sha256sum -c - && sudo bash "$kwvps_tmp" --apply --release=v0.50.1; kwvps_rc=$?; if [ -n "$kwvps_tmp" ]; then rm -f -- "$kwvps_tmp"; fi; (exit "$kwvps_rc")
```

Lệnh dài xác minh SHA-256 của bootstrap từ tag cố định rồi ghim gói `v0.50.1`. Nếu VPS thiếu công cụ tải, cài `curl ca-certificates python3` bằng APT của Ubuntu trước. Sau khi cài chạy `kwvps --doctor`, rồi `kwvps`. Bản này chưa được thử cài mới đầu-cuối trên VPS trắng thứ hai; xem [giới hạn phát hành](docs/RELEASE-NOTES-0.50.1.md) và [quy trình phát hành](docs/PHAT-HANH-GITHUB.md).

## Chạy bản phát triển

Từ thư mục dự án, dùng Bash 5 trở lên:

```bash
bash kwvps --help
bash kwvps --preview
bash kwvps --site-plan example.com 8.3
```

`--preview` chạy trên Git Bash/Windows, không truy vấn quản trị VPS. Nếu mở từ PowerShell trên Windows hoặc thấy lỗi chữ tiếng Việt, dùng `.\scripts\preview-utf8.ps1` và xem [hướng dẫn terminal tiếng Việt](docs/TIENG-VIET-TERMINAL.md). Lệnh này chọn đúng Git Bash và đặt đầu ra UTF-8.

Trên Linux thử nghiệm:

```bash
bash kwvps --doctor
bash kwvps --status
bash kwvps --services
bash kwvps
```

Trên VPS thử nghiệm mới, chạy `bash install.sh --check` trước. Khi điều kiện đạt, `sudo bash install.sh --apply` cài Nginx, PHP 8.3 FPM, MariaDB, Fail2ban, UFW, cron, nano và lệnh `kwvps`; bộ cài không tự bật UFW. Xem [hướng dẫn thử nghiệm](docs/THU-NGHIEM-VPS.md) trước khi áp dụng. Không cần sudo để xem menu; thao tác ghi cần sudo và xác nhận. Truy vấn UFW/Fail2ban/journal có thể cần quyền riêng.

PHP 8.3 của Ubuntu 24.04 phải đạt gói `8.3.6-0ubuntu0.24.04.13` (bản vá backport), không cần mang số upstream 8.3.36. PHP 8.4/8.5 phải đạt 8.4.27/8.5.12; nếu APT hiện tại thiếu gói đạt ngưỡng, menu cài PHP hỏi `y/N` trước khi thêm/cập nhật PPA Ubuntu `ppa:ondrej/php` của Ondřej Surý. KwVPS ưu tiên kho Ubuntu hơn PPA, hiển thị nguồn/candidate và mô phỏng APT trước xác nhận cài. Nếu PPA cần `php-common` mới hơn, menu mô phỏng nâng đúng gói dùng chung này rồi cảnh báo trước khi cài; lệnh `php` CLI mặc định toàn VPS cũng có thể đổi (trên VPS lab đã chuyển từ 8.3 sang 8.5). PHP-FPM của từng site không tự đổi. PHP 7.4 có thể cài từ PPA Ubuntu Ondřej và chọn khi tạo, nhân bản hoặc chuyển site; KwVPS yêu cầu xác nhận riêng mỗi thao tác nhưng không xác minh phiên bản này an toàn. Chỉ cân nhắc cho ứng dụng cũ; không khuyến nghị website Internet. Không dùng kho Debian `deb.sury.org` trên Ubuntu. Xem [PHP releases](https://www.php.net/) và [Ubuntu USN-8948-1](https://ubuntu.com/security/notices/USN-8948-1).

Với VPS thử nghiệm **đã cài KwVPS**, kiểm tra bản mã mới bằng `sudo bash upgrade.sh --check`, sau đó mới chạy `sudo bash upgrade.sh --apply --confirm=UPGRADE-KWVPS`. Đường nâng cấp chỉ thay bộ mã `/opt/kwvps`, giữ bản trước dưới `/opt/kwvps-previous-*`; không cập nhật Ubuntu hoặc service. Không chạy lại `install.sh --apply` để nâng cấp.

## Phần đã có

- 18 nhóm menu, menu con, quay lại bằng 0, thoát Ctrl+C/EOF.
- Header version, RAM theo MemAvailable, disk theo filesystem dữ liệu, swap, ngày VPS.
- Kiểm tra Ubuntu 24.04, kiến trúc, công cụ và systemd.
- Inventory package dịch vụ, package chờ update từ cache apt.
- Socket listen, trạng thái UFW, swap, trạng thái jail Fail2ban.
- Crontab user hiện tại, journal giới hạn 100 dòng của Nginx/MariaDB/cloudflared.
- Trạng thái service và version cloudflared.
- Kiểm tra cú pháp cấu hình Nginx ngay từ menu (có thể cần quyền root và mở log kiểm tra của Nginx).
- Xem kế hoạch thêm site, liệt kê site KwVPS và tạo site HTTP trên VPS thử nghiệm sạch; mỗi site có user và PHP-FPM pool riêng.
- Site mới dùng ID đọc được từ domain: `kwvps.kenhgamez.top` → `kwvpskenhgameztop` (bỏ dấu chấm/gạch; tối đa 29 ký tự). Domain khác tạo cùng ID sẽ bị từ chối với thông báo trùng. Site hash cũ vẫn đọc được để người quản trị gỡ có kiểm soát; nâng cấp không tự xóa chúng.
- Form nhập domain, DB/user/mật khẩu, pool, swap, firewall và Fail2ban cho nhập lại ngay khi sai quy tắc; Enter trống để hủy.
- Dung lượng source, tìm file lớn và đọc access/error log theo site đã quản lý.
- Đưa site HTTP nguyên bản do KwVPS tạo ra khỏi phục vụ: backup source trước, chuyển source/cấu hình sang vùng giữ root-only; không xóa user, log hoặc backup. Có menu phục hồi site đã giữ về đường dẫn cũ.
- Xem cấu hình PHP-FPM pool, service và journal theo site; chỉnh `pm.max_children`/`pm.max_requests` có backup và rollback, hoặc mở bản tạm trong nano rồi kiểm tra trước khi áp. Có menu chọn PHP 8.5/8.4/8.3/7.4; PHP 7.4 yêu cầu xác nhận EOL riêng khi gắn vào site, các phiên bản còn hỗ trợ cần đạt bản vá. Đã thử tạo site 8.4 rồi chuyển sang 8.5 trên VPS lab.
- Sao lưu/khôi phục riêng thư mục source của site KwVPS. Backup nằm tại `/var/backups/kwvps` quyền root-only, có checksum; restore kiểm tra archive, tạo backup trước khi thay và giữ source cũ. Không bao gồm DB, SSL hoặc cấu hình dịch vụ.
- MariaDB: menu 7 mục gồm danh sách DB/user đánh số (chỉ hiện tên), đổi mật khẩu, tạo DB với tên/user/password do bạn chọn, xóa với xác nhận `y/N`, import dump `.sql`/`.sql.gz` từ cùng thư mục backup `/var/backups/kwvps` và export theo danh sách DB. Khi import có thể lọc DB đích theo site hoặc xem tất cả DB. Thư mục backup chỉ root đọc/ghi; cần chuyển file upload vào bằng quyền root. Chỉ thao tác DB do KwVPS quản lý; mật khẩu nằm trong metadata root-only. Import không nguyên tử, tự export DB đích trước, và cần kiểm tra ứng dụng sau thao tác. Không mở MariaDB ra Internet.
- Fail2ban: xem jail/IP bị khóa, ban hoặc unban IPv4 trong jail hiện hữu với xác nhận; không tự viết cấu hình jail. Ban từ chối IP của các phiên SSH đang đăng nhập.
- UFW: xem rule, mở/đóng port TCP/UDP và ban/unban IPv4. KwVPS chỉ gỡ rule do mình tạo, không tự bật UFW và không cho mở công khai cổng 3306. Trên VPS thử nghiệm UFW đã được bật sau khi mở 22/tcp và 80/tcp; firewall nhà cung cấp không thuộc phạm vi KwVPS.
- Swap: xem swap, thêm/gỡ một swapfile riêng tại `/var/lib/kwvps/swapfile`; không động tới swap khác. Trước khi sửa `/etc/fstab`, KwVPS giữ bản sao root-only trong `/var/backups/kwvps`.
- Nginx: phục hồi vhost HTTP gốc của site KwVPS và áp baseline global (`server_tokens off`, giới hạn body 32 MB). Có bản sao root-only và kiểm tra cấu hình/reload; từ chối ghi đè vhost có SSL.
- Cron: xem `/etc/crontab` và crontab của root; mở crontab root bằng nano sau khi lưu bản sao root-only. Không tự chỉnh file trong `/etc/cron.d`.

GitHub Release công khai đã hoạt động; menu Update dùng đường GitHub sau khi cấu hình `uamicpham/kwvps` trong menu. Tự đẩy IP vi phạm từ log Nginx lên Cloudflare và Real IP qua Tunnel vẫn cần kiểm thử đầy đủ. Rate limit Nginx đã trả HTTP 429 trong phép thử loopback, nhưng phép thử này không xác nhận đẩy IP lên Cloudflare. Tunnel/route thật đã trả HTTPS 200; inbound 80/443 đóng và gia hạn HTTP-01 qua Tunnel đã thử. Cloudflare Rate Limiting Free mới qua API dry-run, chưa tạo rule thật. SSH đổi port/key-only tạm gác; ionCube chưa thử loader thật. Phiên bản 0.50.6 lưu API token Cloudflare theo từng site và tự tìm Zone ID bằng token vừa nhập; backup cấu hình domain có thêm Zone ID và token site mã hóa nếu đã cấu hình. Backup vẫn không gồm source, DB, SSL private key, ingress, rate limit, cron hay cấu hình toàn VPS. Các menu còn thiếu hiển thị rõ giới hạn.

## Kiểm thử

```bash
bash tests/smoke.sh
bash tests/system-smoke.sh
shellcheck -x kwvps install.sh upgrade.sh scripts/kwvps-launcher src/*.sh tests/*.sh
bats tests/*.bats
```

Có workflow Ubuntu 24.04 trong `.github/workflows/test.yml`; chỉ chạy trên GitHub sau khi người dùng đưa repository lên. Kiểm thử cục bộ không thay thế integration test trên VPS Ubuntu. Bản đang cài trên VPS đã qua phép thử HTTP/PHP cơ bản và backup/restore source; chưa có restore đầy đủ. Xem `docs/PROGRESS.md` để biết kết quả đã kiểm chứng và phần còn thiếu.

## Tài liệu

- [Hướng dẫn dự kiến và đặc tả đầy đủ](docs/KWVPS-HUONG-DAN-VA-DAC-TA.md)
- [Trạng thái thực tế từng nhóm chức năng](docs/TRANG-THAI-CHUC-NANG.md)

## Cấu trúc

- `docs/`: đặc tả, hướng dẫn và quyết định thiết kế.
- `src/`: mã nguồn sẽ được triển khai.
- `tests/`: kiểm thử sẽ được bổ sung cùng mã nguồn.

## Hướng triển khai

1. Xây dựng khung Bash, menu tiếng Việt, thông tin hệ thống và nhận diện hệ điều hành.
2. Bổ sung kiểm tra quyền, logging che bí mật, xử lý lỗi và kiểm thử.
3. Triển khai từng module theo đặc tả, dùng chung logic quản lý tài nguyên.
4. Kiểm thử trên VPS riêng trước khi phát hành bộ cài GitHub.

## Nguyên tắc

- Viết mã tại thư mục dự án này, đưa bản đã kiểm tra lên VPS thử nghiệm.
- Lưu mã nguồn UTF-8, xuống dòng LF.
- Không commit mật khẩu, SSH private key, Cloudflare token, cấu hình chứa bí mật hoặc backup website.
- Không thao tác thay đổi VPS production để thử tính năng.
- Không tuyên bố hỗ trợ phiên bản Linux chưa kiểm thử.
