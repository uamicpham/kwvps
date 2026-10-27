# KwVPS — Hướng dẫn sử dụng dự kiến và đặc tả chức năng

Phiên bản tài liệu: 0.1 — ngày 21/10/2026. Ngôn ngữ: tiếng Việt.

## Đọc trước khi sử dụng

**Đây là tài liệu thiết kế KwVPS, chưa phải hướng dẫn cho một phần mềm đã hoàn thành.** Các menu, đường dẫn và quy trình bên dưới là yêu cầu để triển khai và kiểm thử. Đã có bộ cài cục bộ thử nghiệm tại `install.sh`, nhưng chưa có repository GitHub được xác nhận, bản phát hành hay kết quả chạy thử trên VPS Ubuntu.

Người dùng yêu cầu hướng dẫn toàn tập LarVPS làm tài liệu trong dự án. Nguồn LarVPS hiện có chỉ gồm ảnh menu chính **v2.0.299** và danh sách chức năng do người dùng cung cấp. Vì chưa có tài liệu chính thức hoặc ảnh từng menu con, không thể khẳng định số thứ tự, câu hỏi và tác động thực tế của từng thao tác LarVPS. Tài liệu này ghi đầy đủ thiết kế KwVPS học hỏi cách nhóm chức năng LarVPS, không giả lập một hướng dẫn LarVPS đã kiểm chứng. Phần cuối ghi cách bổ sung đối chiếu LarVPS.

VPS LarVPS hiện có đang chứa website và dữ liệu thật: **không dùng làm máy thử KwVPS, không cài đè hay tự động chuyển đổi**. Mọi kiểm thử thay đổi hệ thống thực hiện trên VPS thử nghiệm riêng.

Không có tính năng AI router hoặc AI Agent.

## Mục lục

1. Phạm vi, cài đặt và giao diện chung
2. Quản lý site
3. SSL
4. SSH/AuthKey
5. Database
6. PHP
7. Nginx
8. Fail2ban
9. Tiện ích/phpMyAdmin
10. Cron
11. Cache
12. Swap
13. Firewall
14. Disk
15. Logs
16. Update
17. Sao lưu/phục hồi
18. Cloudflare Tunnel
19. Công cụ nâng cao/Cloudflare
20. Liên kết chức năng và nguồn cấu hình dùng chung
21. Quy trình thực tế, xử lý lỗi và tiêu chí nghiệm thu
22. Đối chiếu LarVPS và tài liệu tham khảo

## 1. Phạm vi, cài đặt và giao diện chung

### 1.1. Hệ điều hành và nền tảng

- Mục tiêu đầu tiên: Ubuntu Server 24.04 LTS, systemd, máy ảo/VPS đầy đủ.
- Ubuntu/Debian phiên bản khác chỉ được công bố hỗ trợ sau khi có kiểm thử riêng. Không suy ra tương thích chỉ vì dùng apt.
- Kiến trúc máy phải được nhận diện. Chỉ cho phép cài các gói và binary phù hợp; ionCube và cloudflared cần kiểm tra riêng kiến trúc/phiên bản.
- Stack dự kiến: Nginx, PHP-FPM đa phiên bản, MariaDB, Redis, Fail2ban, UFW. Cloudflared và phpMyAdmin là thành phần tùy chọn.
- Không tự cài tất cả phiên bản PHP. Repository bổ sung và phiên bản ngoài kho Ubuntu phải được thông báo, xác minh nguồn và được người dùng chấp thuận.
- Bản đầu tiên cài trên VPS sạch. Nếu phát hiện LarVPS, control panel, web stack hoặc cấu hình xung đột: dừng và báo, không ghi đè.

### 1.2. Cài đặt từ GitHub

Yêu cầu: một lệnh cài đặt được công bố tại repository chính thức sau khi dự án có release. Chưa có tên tài khoản/repository nên **chưa thể cung cấp URL cài thật**.

Quy trình bộ cài phải thực hiện:

1. Nhận diện hệ điều hành, kiến trúc, quyền sudo/root, dung lượng, RAM, DNS và kết nối kho gói.
2. Phát hiện dịch vụ và panel hiện có; kiểm tra trạng thái apt/dpkg, không xóa lock đang được tiến trình khác sử dụng.
3. Hiện các thành phần sẽ cài và những thay đổi, yêu cầu xác nhận.
4. Tải một release được ghim phiên bản qua HTTPS; xác minh tính toàn vẹn và nguồn phát hành. Checksum cùng nguồn chỉ hỗ trợ phát hiện hỏng tải, không thay thế xác thực chữ ký/nguồn tin cậy.
5. Cài vào thư mục do KwVPS quản lý, tạo lệnh `kwvps`, ghi phiên bản và trạng thái cài đặt.
6. Kiểm tra cấu hình, dịch vụ và hiển thị kết quả; nếu thất bại phải chỉ rõ bước hoàn thành/dang dở.

Không hướng dẫn chạy một URL chưa tồn tại, không mặc định thực thi nhánh main thay đổi liên tục với quyền root. Cài lại cùng phiên bản không được tạo trùng cấu hình hoặc xóa dữ liệu.

Sau khi bộ cài được triển khai và cài thành công, lệnh mở menu là:

```text
kwvps
```

### 1.3. Đầu trang

```text
KwVPS <version>
Disk: 8/71 GB | Ram: 1776/7751 MB | Swap: 0/2047 MB | Ngay: 2026-07-15
```

Các con số trên là mẫu do người dùng cung cấp, không phải số đo máy hiện tại. Khi chạy thật:

- Version lấy từ bản KwVPS đang cài.
- Disk hiển thị đã dùng/tổng dung lượng filesystem chứa dữ liệu site; ghi thêm mount nếu có nhiều ổ. Mục Disk cung cấp chi tiết từng site.
- RAM hiển thị đã dùng/tổng; tính đã dùng theo tổng trừ bộ nhớ available, tránh xem toàn bộ cache là RAM không thể dùng.
- Swap hiển thị đã dùng/tổng, bằng 0/0 nếu chưa có swap.
- Ngày lấy theo đồng hồ và múi giờ của VPS, không hardcode, không tự đổi múi giờ. Đơn vị hiển thị và cách tính phải thống nhất.
- Không thu thập IP công khai từ dịch vụ bên thứ ba chỉ để vẽ menu nếu không cần.

### 1.4. Menu chính

Danh sách người dùng gồm 19 nhóm yêu cầu, trong đó nhóm 1 là bộ cài/giao diện. Vì vậy menu chính có 18 mục nghiệp vụ:

```text
 1. Quản lý site                  10. Quản lý cache
 2. Quản lý SSL                   11. Quản lý swap
 3. Quản lý SSH/AuthKey           12. Quản lý Firewall
 4. Quản lý DB                    13. Quản lý Disk
 5. Quản lý PHP                   14. Quản lý Logs
 6. Quản lý Nginx                 15. Quản lý Update
 7. Quản lý Fail2ban              16. Sao lưu/phục hồi
 8. Quản lý Tiện ích              17. Quản lý Cloudflare Tunnel
 9. Quản lý cron                  18. Công cụ nâng cao
 0. Quay lại / thoát ở menu gốc
```

Mọi menu con có `0. Quay lại`, trở về đúng một cấp. Menu gốc không có cấp cha nên 0 thoát. `Ctrl+C` yêu cầu hủy thao tác và thoát toàn bộ KwVPS, không chỉ quay lại một menu.

Ngoại lệ kỹ thuật phải nói rõ trên màn hình: khi nano đang mở, Ctrl+C là phím của nano, không phải thoát KwVPS; dùng Ctrl+X để đóng nano rồi Ctrl+C để thoát. Khi trình quản lý gói đang ghi dữ liệu, không cưỡng bức kill khiến dpkg hỏng; ghi nhận yêu cầu thoát và chờ điểm dừng an toàn. Nếu yêu cầu Ctrl+C thoát ngay cả trong nano là bắt buộc tuyệt đối thì cần thiết kế trình chỉnh sửa khác, không thể hứa hành vi đó với nano nguyên bản.

### 1.5. Quy ước thao tác

- Chọn đối tượng từ danh sách site đã đăng ký, không lấy chuỗi nhập làm đường dẫn hoặc lệnh shell trực tiếp.
- Hiện đối tượng, phạm vi, thay đổi, ảnh hưởng và cách khôi phục trước khi ghi.
- Mặc định từ chối khi câu hỏi xác nhận không có trả lời; thao tác xóa yêu cầu nhập lại đúng domain/tên DB.
- Các bước đọc chỉ cần quyền tối thiểu; thao tác ghi yêu cầu sudo thích hợp.
- Có chế độ xem trước đối với thao tác thay đổi; không hứa mô phỏng hoàn toàn mọi hook cài gói.
- Sao lưu cấu hình trước sửa; kiểm tra cú pháp, restart dịch vụ liên quan rồi xác nhận trạng thái active; thử health check site khi thay đường phục vụ. Ghi nhật ký không chứa bí mật.
- Không tự reboot, không xóa database theo tên đoán, không dùng phân quyền 777 để chữa lỗi.
- Ctrl+C dọn file tạm/khóa; không tự nhận đã rollback những thay đổi gói hoặc dữ liệu không thể hoàn tác.

## 2. Quản lý site — menu chính 1

```text
1. Danh sách site
2. Thêm domain/subdomain
3. Đổi tên miền
4. Clone site
5. Xóa site
6. Phân quyền site
7. Laravel theo site (menu con)
0. Quay lại
```

Bản thử `0.37.0-dev`: mục 3 đổi tên miền cho site HTTP nguyên bản (không có SSL, tùy biến vhost/pool hoặc DB legacy); đổi user/home/pool/vhost/metadata và liên kết DB tự đặt tên, có backup và rollback. Không tự sửa DNS, URL trong ứng dụng, cron hoặc Tunnel. Mục 4 clone **source/code** và tạo site HTTP mới sau xác nhận `y/N`; DB, SSL, DNS, cron không được sao chép. Mục 5 hiển thị tài nguyên rồi chọn (1) xóa site và giữ vùng phục hồi hoặc (2) xóa sạch, không giữ vùng phục hồi. Cả hai yêu cầu nhập lại domain; DB và chứng chỉ không bị xóa. Khi thêm domain đang trong vùng giữ, menu đề nghị phục hồi hoặc xóa bản giữ rồi tạo site mới; thao tác xóa bản giữ yêu cầu nhập lại domain. Mục 6 đặt lại owner/group của source, giữ mode và từ chối cây có link. Mục 7 là menu Laravel dùng chung từ 0.50.8. Menu Backup có phục hồi hoặc xóa sạch **gói site đã giữ**. Các đoạn dưới là đặc tả mục tiêu đầy đủ hơn.

### Danh sách site

Hiện domain, mã site cố định, document root, user sở hữu, PHP, trạng thái Nginx, SSL, cache và chế độ truy cập (trực tiếp/Cloudflare proxy/Tunnel). Không hiển thị mật khẩu DB. Cấu hình có trên ổ đĩa nhưng không do KwVPS quản lý phải gắn nhãn, không tự nhận quản lý.

### Thêm domain/subdomain

1. Nhập tên miền không kèm scheme/path; chuẩn hóa và kiểm tra trùng, xử lý IDN có chủ đích.
2. Chọn phiên bản PHP-FPM riêng cho domain. Nếu chưa cài, chuyển sang luồng cài PHP dùng chung sau xác nhận.
3. Chọn document root và chế độ truy cập. Đường dẫn phải ở vùng dữ liệu được quản lý, không đi xuyên symlink ra ngoài.
4. Tạo user/pool riêng cho site, thư mục và cấu hình Nginx. Mô hình cách ly mặc định: mỗi site có user và pool riêng.
5. Tùy chọn tạo DB thông qua module DB, không lặp logic tạo tài khoản.
6. Kiểm tra Nginx/PHP-FPM, áp dụng và thử HTTP/health check. DNS chưa trỏ đúng thì báo rõ, không kết luận site truy cập công khai được.
7. Tùy chọn chuyển sang menu SSL; không cấp chứng chỉ nếu điều kiện xác thực chưa đáp ứng.

Hai domain có thể chọn hai PHP version khác nhau; thêm site mới không đổi PHP của site cũ hoặc PHP CLI toàn hệ thống.

### Đổi tên miền

Chọn site → nhập tên mới → xem kế hoạch → xác nhận `y/N`. Bản hiện tại đổi site ID/user, thư mục site, pool, socket, vhost, metadata DB liên kết và nhãn ingress; tên DB/user DB giữ nguyên. Vhost HTTP mẫu và Laravel release do KwVPS tạo được hỗ trợ, gồm lớp Real IP cho Tunnel. Vhost SSL, FastCGI cache hoặc Nginx chỉnh tay vẫn bị từ chối để tránh ghi đè cấu hình chưa thể chuyển an toàn.

Nếu site có connector Tunnel riêng, KwVPS chuyển token giữ nguyên nội dung sang site ID mới và chuyển unit systemd tương ứng. Service mới giữ trạng thái đang bật/đang chạy của service cũ; nếu đổi tên thất bại, KwVPS thử hoàn tác cả connector. Bản sao token cũ được giữ trong vùng backup root-only của giao dịch. **Bạn phải tự đổi hostname route/DNS trong Cloudflare**; KwVPS không cập nhật route bằng API. Trong lúc route chưa đổi, domain mới có thể chưa truy cập được. URL trong `.env`/ứng dụng và nội dung database không tự thay; không tự tạo redirect hay chứng chỉ SSL mới.

### Clone

Chọn nguồn → domain đích → PHP đích → chọn copy source và có clone DB không → xem dung lượng → xác nhận. Tạo user, pool và DB credentials mới cho đích. Không copy private key SSL hoặc token Cloudflare sang site mới một cách ngầm định. Không bật cron, email gửi ra, thanh toán/webhook của bản clone theo mặc định; kiểm tra ứng dụng trước mở công khai.

### Xóa

Hiện riêng các lựa chọn: gỡ cấu hình, xóa source, xóa DB liên kết, xóa backup. Mặc định giữ DB và backup. Kiểm tra DB, chứng chỉ hoặc Tunnel có dùng chung; chỉ xóa tài nguyên được xác nhận thuộc site và không còn phụ thuộc. Không xóa cả Tunnel nhiều hostname. Nên đưa source vào vùng lưu tạm có thời hạn, ghi cách khôi phục thay vì xóa vĩnh viễn ngay.

### Phân quyền

Hiện owner/group/mode dự kiến; cấp quyền ghi cho đúng thư mục ứng dụng yêu cầu. Không thay quyền đệ quy toàn máy. Bí mật ứng dụng không được public qua document root. Phân quyền phpMyAdmin thuộc menu Tiện ích, không được cuốn theo site.
Từ bản 0.50.13: chức năng Phân lại quyền hạn (`kw_site_permissions`) hỗ trợ hoàn toàn các symlink nội bộ của site (Laravel `current`, `storage`, `.env`), kiểm tra an toàn bằng Python ngăn chặn symlink trỏ ra ngoài `$KW_SITE_ROOT`. Đồng thời tự động đặt quyền chuẩn bảo mật `0600` cho `deploy/shared/.env` (thuộc user site) và `0750` cho thư mục / `0660` cho file trong `deploy/shared/storage` (nhóm `www-data` ghi log/cache). Loại bỏ rào cản hardlink để tương thích với các dự án dùng `pnpm` hoặc Git.

### Laravel theo site (từ 0.50.8; chưa thử đầu-cuối trên VPS)

Chọn site theo số, xem kế hoạch rồi xác nhận `y/N`; không cần nhập tên dự án vì thư mục cha đã theo site ID. KwVPS tạo `source/` để clone Git và `deploy/releases/`, `deploy/shared/storage/` cùng các thư mục `app/public`, `app/private`, `logs`, `framework/cache/data`, `framework/sessions`, `framework/views`. Quyền thư mục thuộc user riêng của site; nhánh upload công khai có nhóm `www-data`. Nếu `source/`, `deploy/` hoặc cấu trúc cũ có tiền tố `*-source`/`*-deploy` đã tồn tại, lệnh từ chối, không ghi đè; không tự chuyển thư mục cũ.

Menu con gồm: (1) chuẩn bị thư mục, (2) xem trạng thái/công cụ và chọn cài công cụ còn thiếu, (3) clone Git vào `source/`, (4) pull nhanh nhánh hiện tại, (5) sửa `deploy/shared/.env` bằng nano dưới user site, (6) tạo và kích hoạt release. Mục kiểm tra cho chọn số để cài riêng Git, Composer, PHP CLI đúng phiên bản site, tar/curl/nano, Node.js/npm, GnuPG, pnpm hoặc Yarn; `0` quay lại. Không cần cài cả pnpm lẫn Yarn nếu dự án không dùng. APT được mô phỏng trước khi hỏi `y/N` và từ chối kế hoạch gỡ package. PHP CLI được kiểm tra nguồn và ngưỡng bản vá như PHP-FPM; PHP 7.4 chỉ chấp nhận PPA Ubuntu Ondřej và vẫn có cảnh báo EOL. Nếu VPS đã có Node/npm cũ, bản sửa đang kiểm thử sẽ cài Node.js 24 riêng dưới `/usr/local/lib/kwvps/nodejs` từ gói NodeSource đã xác minh chữ ký/chỉ mục và SHA-256; không thay `node`/`npm` toàn VPS hay PATH chung. pnpm/Yarn dùng shim Corepack; khi dùng Node riêng, shim cũng ở vùng riêng đó. Màn hình trạng thái không tự cài gì. Chưa kiểm thử đường cài Node riêng đầu-cuối trên VPS.

Nếu APT từ chối chữ ký của NodeSource hoặc candidate không đúng Node.js 24, KwVPS dừng và không nới lỏng kiểm tra chữ ký; kiểm tra lại kho trước khi thử cài. Tham khảo [NodeSource](https://github.com/nodesource/distributions/blob/master/DEV_README.md), [Corepack](https://github.com/nodejs/corepack) và [Yarn](https://yarnpkg.com/getting-started/install) để hiểu nguồn và cơ chế lựa chọn phiên bản frontend.

Clone chấp nhận HTTPS công khai hoặc SSH GitHub dạng `git@github.com:owner/repo.git`. Khi chọn mục 3 với URL SSH GitHub, KwVPS tạo khóa Ed25519 **riêng cho user của site** nếu chưa có, hoặc dùng lại khóa hiện có và hiển thị lại **public key**. Không tạo lại/ghi đè private key mỗi lần clone; vì vậy nếu lần đầu thêm key vào GitHub thất bại, chọn lại mục 3 vẫn lấy được cùng public key. HTTPS công khai không cần Deploy Key. Không nhập token/mật khẩu GitHub vào URL hay gửi private key vào chat.

Với repository riêng tư: sao chép nguyên dòng public key được menu hiển thị (bắt đầu bằng `ssh-ed25519`), mở repository trên GitHub → **Settings → Deploy keys → Add deploy key**, đặt tên dễ nhận diện và dán key; để **Allow write access** tắt nếu chỉ clone/pull. Sau khi GitHub lưu key, quay lại màn hình KwVPS đang chờ để tiếp tục clone. Nếu lần đầu clone lỗi, chọn lại mục 3: menu hiện lại cùng public key để kiểm tra trên GitHub. Nếu GitHub báo key đã được dùng, kiểm tra Deploy keys của repository đã thêm trước đó. KwVPS không tự đăng ký key trên GitHub. Deploy Key chỉ cấp quyền cho repository được gắn, không thay thế quyền truy cập của tài khoản GitHub. Pull tiếp tục dùng khóa của user site đó. Không dùng khóa SSH của `root`/`ubuntu` để thay cho khóa của site.

Khóa riêng nằm trong thư mục của user site; PHP-FPM của site hiện chạy cùng user đó. Nếu ứng dụng PHP bị xâm nhập, kẻ tấn công có thể đọc khóa, vì vậy **chỉ gắn Deploy Key quyền đọc cho đúng một repository**, không cấp quyền ghi hay dùng khóa tài khoản GitHub có phạm vi rộng. Các gói backup KwVPS hiện không mang theo khóa SSH này: khi chuyển VPS, tạo khóa mới trên VPS đích, đăng ký public key mới vào GitHub rồi gỡ Deploy Key cũ khỏi repository sau khi chuyển xong.

SSH còn phải xác minh danh tính máy chủ `github.com` qua `known_hosts` của user site. Ở kết nối SSH đầu tiên, nếu có lời nhắc chấp nhận host key, người dùng cần tự đối chiếu fingerprint với [tài liệu chính thức của GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints) trước khi xác nhận; KwVPS không tự tin cậy host key lấy từ mạng. Không tắt `StrictHostKeyChecking` hoặc chấp nhận fingerprint lạ chỉ để clone được. Nếu host key thay đổi hoặc không xác minh được, dừng clone và kiểm tra nguyên nhân. Pull từ chối source có sửa đổi và chỉ dùng fast-forward. Mục Deploy cũng tự pull nhánh hiện tại trước khi đóng gói, nên sau khi đã clone và chuẩn bị `.env` có thể chỉ chọn Deploy; mục Pull riêng dùng khi muốn cập nhật `source/` mà chưa đổi website. Deploy cần `composer.lock`; frontend có thể tự chọn theo `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, chọn công cụ cụ thể hoặc bỏ qua nếu assets đã có sẵn. Composer và script build của project chạy dưới user site, không phải root. KwVPS không gọi `scripts/deploy.sh` của ứng dụng.

Mục **Sửa .env** tạo `deploy/shared/.env` bằng user riêng của site nếu chưa có. Nếu file đã có nhưng thuộc `root` hoặc user site với owner/quyền chưa đúng, menu chỉ hiển thị metadata (owner, nhóm, quyền, số hardlink), không in nội dung bí mật; sau khi hỏi `y/N`, menu mới sửa owner/quyền của đúng file `.env` đã chọn thành user site và `0600`, không thay nội dung. Menu từ chối symlink, hardlink, file không phải file thường hoặc file thuộc user khác; không phân quyền đệ quy. Nếu không đồng ý sửa, file được giữ nguyên. **Deploy không tự sửa quyền**: nó từ chối `.env` chưa an toàn và yêu cầu quay lại mục Sửa .env.

Release dùng `deploy/shared/.env` (user site, `0600`) và `deploy/shared/storage`; `deploy/current` là symlink chỉ được tạo sau khi build thành công. Nginx tự chuyển root sang `deploy/current/public` cho mẫu vhost HTTP, Let's Encrypt, ZeroSSL hoặc paid SSL nguyên bản, bao gồm lớp Real IP do KwVPS quản lý của site Tunnel. Có thể cấp SSL trước hoặc sau khi kích hoạt Laravel nếu vhost còn đúng mẫu KwVPS; HTTP-01 vẫn đọc từ `public/` cũ. Sau khi build, menu hỏi có chạy migration không (mặc định Không). Nếu chọn Có, KwVPS chạy `php<version> artisan migrate --force --no-interaction` bằng user site trên release mới **trước khi đổi `current`**. Có thể dùng lệnh `sudo kwvps --laravel-deploy DOMAIN --migrate` (bỏ `--migrate` để không chạy); lệnh vẫn hỏi xác nhận `y/N`. Migration phải tương thích với release đang phục vụ; nên backup DB trước. Lỗi migration không đổi `current`, nhưng DB có thể đã thay đổi một phần. Rollback release/vhost **không rollback DB**. Sau khi `nginx -t` và restart, KwVPS gửi một yêu cầu loopback, kiểm tra `php-fpm<version> -t`, reload service PHP-FPM của phiên bản site, xác nhận service active rồi gửi yêu cầu loopback lần nữa. PHP-FPM dùng chung cho mọi site cùng phiên bản nên reload có thể ảnh hưởng ngắn các site đó; lỗi reload/health sẽ hoàn tác release và thử reload lại worker cũ. Cho phép mã HTTP 1xx–4xx và HTTP 503 (nhận diện chế độ bảo trì `php artisan down` của Laravel là hợp lệ); chỉ mã lỗi mạng hoặc HTTP 5xx khác mới trả về release/vhost trước. Không tự chạy seed, queue restart, cron, lệnh dự án khác hoặc kiểm tra endpoint/asset đặc thù. Vì vậy không bảo đảm đủ cho mọi ứng dụng Laravel; ví dụ dự án cần Filament/Livewire publish, cache đặc thù hoặc queue worker phải được đối chiếu trước khi bỏ script deploy riêng. Nếu Nginx tùy biến, cấu trúc Laravel khác chuẩn, repo có submodule/symlink trong `public/`, thiếu công cụ build hoặc `composer.lock`, thao tác dừng trước khi đổi website. Các release thất bại được giữ để kiểm tra, không tự xóa. Đổi tên miền hỗ trợ site Laravel release đang kích hoạt nếu vhost HTTP còn đúng mẫu KwVPS; URL ứng dụng vẫn cần cập nhật riêng. Backup source/code hiện chỉ chứa `public/`; source, release, storage, `.env` và DB cần sao lưu riêng trước khi chuyển VPS.

## 3. SSL — menu chính 2

Trạng thái bản thử `0.37.0-dev`: mục 1 hiển thị trạng thái SSL của site KwVPS (ngày hết hạn cần `sudo`), mục 2 cấp ACME HTTP-01 cho site HTTP có vhost nguyên bản, mục 3 nhập paid SSL cho site HTTP nguyên bản, mục 4 liệt kê site chưa SSL. Mục 5 đổi ACME provider mặc định giữa Let’s Encrypt và ZeroSSL cho lần cấp mới; ZeroSSL cần EAB nhập trên VPS, chưa thử cấp thật. Mục 2 chưa hỗ trợ cấp lại chứng chỉ sẵn có, DNS-01 hoặc wildcard. Trên VPS thử nghiệm, `kwvps.kenhgamez.top` đã cấp Let's Encrypt thành công; paid SSL đã thử bằng chứng chỉ tự ký trên site lab, không phải chứng chỉ thương mại thật. Không tự mở cổng 80/443 từ menu SSL.

```text
1. Xem SSL theo domain
2. Cấp/gia hạn Let's Encrypt
3. Thêm/thay paid SSL
4. Quản lý domain không SSL
5. Đổi ACME provider
0. Quay lại
```

- **Xem SSL:** domain/SAN, issuer, ngày hết hạn, trạng thái gia hạn và chứng chỉ origin thực tế. Phân biệt TLS ở Cloudflare edge với TLS từ Cloudflare tới origin; không dựa riêng ổ khóa trình duyệt.
- **Let's Encrypt:** chọn domain/SAN, email đăng ký, HTTP-01 hoặc DNS-01; kiểm tra DNS A/AAAA và khả năng challenge. Wildcard cần DNS-01. Dùng staging để thử trước, tránh rate limit. Cài chứng chỉ sau khi kiểm tra key/certificate khớp, chuỗi đầy đủ; thử gia hạn và lịch gia hạn.
- **Paid SSL:** chọn certificate, intermediate chain và private key trên VPS; kiểm tra quyền đọc, hostname, thời hạn và key khớp. Không yêu cầu dán private key vào chat/log. Không giả định tự gia hạn như ACME.

  Bản thử hiện tại: upload `fullchain.pem` và private key `.pem` vào `/home/ssl` (thư mục/file thuộc root, thư mục không cho nhóm/người khác ghi, private key `0600`). Vào menu SSL → Thêm paid SSL → chọn site theo số → nhập tên hai file, không nhập đường dẫn hay nội dung key → xác nhận `y/N`. Chỉ áp cho site còn vhost HTTP nguyên bản; nếu site đã có TLS, thao tác dừng và không ghi đè. KwVPS chép cert/key vào `/etc/kwvps/certs/<site-id>/`, kiểm tra Nginx và HTTPS, giữ backup vhost. Chứng chỉ trả phí **không tự gia hạn**; cần theo dõi hạn và xử lý thủ công trước khi hết hạn.
- **Domain không SSL:** liệt kê, cấp SSL hoặc xác nhận tiếp tục HTTP. Không ép redirect HTTPS khi origin chưa có cấu hình hợp lệ. Có thể dùng HTTP loopback sau Tunnel như một chế độ riêng, không đồng nhất với HTTP công khai.
- **Đổi ACME provider:** xác định áp dụng cho một site hay mặc định site mới; giữ chứng chỉ đang hoạt động cho đến khi cấp mới thành công. Hỗ trợ EAB nếu provider yêu cầu, giữ credentials riêng và bảo mật. Thao tác cấp lại phải hiện provider đang chọn; lựa chọn Let's Encrypt vẫn là lựa chọn cụ thể, không âm thầm đổi nhà cung cấp.

Khi 80 đóng: HTTP-01 trực tiếp sẽ thất bại; DNS-01 là hướng ưu tiên. Nếu HTTP-01 được chuyển qua Tunnel/Cloudflare thì phải kiểm thử đường challenge công khai, không tự suy ra hợp lệ. Không mở cổng toàn VPS âm thầm để gia hạn.

## 4. SSH/AuthKey — menu chính 3

Bản thử `0.30.0-dev` có **đổi mật khẩu** bằng `passwd` tương tác và **quản lý public key ed25519** cho root/ubuntu (xem fingerprint, thêm, xóa theo số). Xóa key yêu cầu nhập lại fingerprint, không cho xóa khóa cuối cùng. Đã thử chu trình thêm/xóa key tạm trên VPS thử nghiệm và xác nhận `authorized_keys` trở về đúng nội dung ban đầu. Mục **giới hạn đăng nhập** cho đặt `MaxAuthTries` (2–10), `MaxSessions` (1–20), `LoginGraceTime` (30–120 giây) bằng file `/etc/ssh/sshd_config.d/70-kwvps-limits.conf`; kiểm tra cú pháp/giá trị hiệu lực và hoàn tác khi lỗi. Đã thử với giá trị mặc định và đăng nhập phiên SSH mới. Đổi mật khẩu chưa thử tương tác; đổi port và key-only bên dưới vẫn là đặc tả, chưa có thao tác ghi trong menu.

```text
1. Xem cấu hình SSH hiện tại
2. Đổi port SSH
3. Đổi mật khẩu tài khoản SSH
4. Giới hạn đăng nhập
5. Quản lý public key
6. Bật/tắt chế độ chỉ AuthKey
0. Quay lại
```

“Mật khẩu SSH” là mật khẩu của tài khoản Linux được chọn, không có mật khẩu SSH chung. Đổi mật khẩu không tự bật lại xác thực bằng mật khẩu nếu đang key-only.

- **Đổi port:** kiểm tra port hợp lệ/chưa bị chiếm, nhận diện service/socket activation của SSH trên Ubuntu 24.04, cấu hình drop-in/cloud-init và giá trị thực có hiệu lực. Cho phép cổng mới qua module Firewall; nhắc firewall nhà cung cấp phải được điều chỉnh riêng. Giữ cổng/phiên cũ cho đến khi đăng nhập phiên mới thành công. Có phương án khôi phục có thời hạn; không tự khóa đường cứu hộ.
- **Giới hạn đăng nhập:** allowlist user/group, root login, số lần thử, timeout và tùy chọn allowlist IP. Cảnh báo IP động, IPv6, proxy/bastion. Xác nhận còn ít nhất một tài khoản quản trị có thể đăng nhập.
- **Public key:** thêm/liệt kê/xóa key của tài khoản; kiểm tra định dạng và quyền thư mục SSH. Không nhận private key. Xóa key cuối cùng của quản trị phải có cảnh báo và đường truy cập thay thế đã kiểm chứng.
- **AuthKey-only:** thêm key trước → kiểm tra cấu hình SSH → người dùng xác nhận đăng nhập phiên SSH mới bằng key → tắt password/keyboard-interactive theo cấu hình hiệu lực → áp dụng an toàn. Không chỉ dựa trên việc file authorized_keys tồn tại.

Mất kết nối: dùng console nhà cung cấp và bản cấu hình trước thay đổi. Không thực hiện thử trên VPS LarVPS production.

## 5. DB — menu chính 4

Bản hiện tại có đúng thứ tự menu bên dưới. Chỉ liệt kê/ghi DB do KwVPS quản lý, gồm DB per-site cũ và DB mới tự đặt tên. Danh sách DB/user chỉ hiện số thứ tự và tên. Tạo DB mới chọn site theo số rồi nhập tên DB, user, mật khẩu (12–128 ký tự trong tập chữ/số và `_!@#%+=.-`). Khi tạo hoặc đổi mật khẩu DB, ký tự sẽ hiện trong terminal lúc nhập để bạn kiểm tra; KwVPS không in lại mật khẩu sau đó. Chỉ nhập khi màn hình PuTTY không bị chia sẻ hoặc ghi hình. Import chọn file `.sql`/`.sql.gz` trong cùng thư mục backup `/var/backups/kwvps` theo số trước, sau đó chọn xem tất cả DB hoặc lọc theo site, cuối cùng chọn DB đích. Bộ lọc site chỉ đổi danh sách chọn, không tự tạo DB mới. Menu cảnh báo nếu DB đã có bảng nhưng **không tự export hiện trạng**; hãy chọn Export DB thủ công trước khi import nếu cần giữ dữ liệu đích. Import dùng user quyền giới hạn và có thể để lại dữ liệu một phần nếu SQL lỗi; không có rollback tự động. Export DB mới chỉ tạo một file `db-<tên-DB>-YYYYMMDD-HHMMSS[-N].sql.gz`, không kèm `.sha256`; file backup cũ được giữ nguyên và vẫn có thể dùng để restore. Thư mục backup chỉ root truy cập, nên file từ máy khác phải được chuyển vào đó bằng quyền root; file cũ trong `/home/db` không còn được quét. Nếu file đã upload vào `/home/db`, người quản trị cần tự sao chép file cụ thể vào thư mục backup với quyền `root:root`, chế độ `0600`, rồi kiểm tra tên và dung lượng trước khi import. Không tự chuyển hay xóa file cũ khi nâng cấp. Xóa hiển thị DB/user/site và hỏi `y/N`; thao tác vẫn tự giữ export. Đổi pass không tự cập nhật `.env` của ứng dụng. Những mục bên dưới mô tả mục tiêu rộng hơn, không phải mọi tùy chọn đã có.

```text
1. Danh sách DB
2. Danh sách User DB
3. Đổi Pass Database (User DB)
4. Tạo DB
5. Xóa DB
6. Import DB
7. Export DB
0. Quay lại
```

Nền tảng mặc định đề xuất: MariaDB. Không tuyên bố hỗ trợ MySQL hay chuyển đổi qua lại cho đến khi có kiểm thử.

- **Danh sách:** tên DB, dung lượng ước tính, site liên kết và user được cấp quyền; không đọc nội dung bảng hoặc in mật khẩu.
- **Tạo:** nhập tên hợp lệ, chọn charset/collation phù hợp ứng dụng, tạo user riêng chỉ có quyền cần thiết trên DB đó. Bí mật lưu quyền hạn chế; không đưa vào command line, Git hoặc log.
- **Xóa:** chặn DB hệ thống, hiện site phụ thuộc, hỏi `y/N`. Bản thử tự export trước khi DROP và chỉ xóa user thuộc DB KwVPS đã chọn.
- **Import:** chọn file và DB đích; kiểm tra định dạng/dung lượng, cảnh báo SQL có thể chứa DROP/CREATE/USE hoặc tác động ngoài dự kiến. Dùng tài khoản giới hạn quyền. Nếu cần giữ DB đích, tự chọn Export DB trước; import không tự backup, lỗi có thể để dữ liệu dở dang và không đảm bảo rollback giao dịch toàn file.
- **Export:** chọn DB; bản hiện tại tạo một file `.sql.gz` trong vùng backup, không kèm file hash. Dump cần tính tới routines/triggers/events và quyền cần thiết. Kiểm tra exit code, định dạng gzip và thử restore định kỳ; file tồn tại không chứng minh dump tốt. Không có checksum riêng nên không thể dùng KwVPS để xác nhận file chưa bị thay đổi sau khi sao chép.
- **Remote:** chọn bind address, IP/CIDR nguồn, TLS và user remote giới hạn. Mở đúng port/nguồn qua module Firewall, kiểm tra firewall nhà cung cấp. Mặc định không mở toàn Internet, không cấp remote root. Nên ưu tiên mạng riêng hoặc SSH tunnel nếu phù hợp.

## 6. PHP — menu chính 5

Bản thử hiện tại: trước tiên chọn site bằng số. Menu PHP có mục kiểm tra bản vá theo gói thực tế; cấu hình pool cho chỉnh `pm.max_children` (1–128) hoặc `pm.max_requests` (1–10000), sao lưu, kiểm tra `php-fpm<version> -t`, restart rồi xác nhận service active. Mục đổi phiên bản chọn 8.5/8.4/8.3/7.4; PHP 7.4 có thể dùng khi tạo/clone/đổi tên/chuyển site sau xác nhận EOL riêng cho thao tác, các bản còn hỗ trợ phải đạt bản vá. Ubuntu 24.04 PHP 8.3 cần revision `8.3.6-0ubuntu0.24.04.13` trở lên; upstream 8.3/8.4/8.5 cần tối thiểu 8.3.36/8.4.27/8.5.12. Mục **Cài gói PHP-FPM** dùng APT hiện tại trước; nếu thiếu package phù hợp, hỏi `y/N` trước khi thêm/cập nhật PPA Ubuntu `ppa:ondrej/php` của Ondřej Surý, không dùng kho Debian `deb.sury.org`. Khi thêm nguồn mới, KwVPS ghim ưu tiên PPA ở mức 100 để gói Ubuntu vẫn được ưu tiên; kiểm tra nguồn candidate, kiểm tra bản vá với PHP 8.x, mô phỏng APT và hỏi trước khi cài PHP-FPM cùng extension. PHP 7.4 luôn được đánh dấu EOL/chưa xác minh an toàn. Custom pool mở bản tạm trong nano, không cho đổi user/group/socket/ràng buộc an toàn, kiểm tra trước khi áp. Mục ionCube nhận file loader Linux x86-64 chính thức tại `/root/kwvps-loaders/ioncube_loader_lin_<version>.so` cùng SHA-256 lấy độc lập; bật/tắt cho **toàn bộ PHP-FPM version**, không phải từng site. Kiểm tra bằng PHP CLI, FPM và có rollback khi bật lỗi. Chưa thử với loader thật. Những mô tả mở rộng bên dưới là đặc tả mục tiêu, không đồng nghĩa đã có đủ trong bản thử.

Trên Ubuntu 24.04 lab, PPA có PHP 8.4.27/8.5.12 nhưng cần `php-common` mới hơn bản Ubuntu. Nếu mô phỏng APT báo đúng phụ thuộc này, KwVPS kiểm tra nguồn và mức phiên bản `php-common` từ cùng PPA, thêm đúng gói vào kế hoạch, mô phỏng lại với điều kiện không gỡ package rồi mới hỏi xác nhận cài. Đây là gói dùng chung, có thể ảnh hưởng các bản PHP đã cài; việc cài PHP CLI cũng có thể đổi lệnh `php` mặc định toàn VPS (lab đã chuyển từ 8.3 sang 8.5). Phiên bản FPM gắn với từng site không tự thay đổi. Trên VPS lab đã thử tạo site với 8.4 và chuyển sang 8.5, kiểm socket/HTTP 200; site thử đã xóa sạch sau đó.

```text
1. Danh sách PHP và site đang sử dụng
2. Cấu hình pool từng site
3. Đổi PHP version của site
4. Quản lý ionCube theo version
5. Sửa custom pool bằng nano
0. Quay lại
```

- **Pool:** chọn site; sửa pm mode, max_children, các giới hạn worker, timeout, memory/upload và slowlog trong phạm vi thích hợp. Hiện ngân sách RAM tổng vì nhiều pool có thể cùng hoạt động. Không tính max_children chỉ từ RAM tổng mà bỏ qua DB/Redis/hệ điều hành.
- **Đổi version:** kiểm tra PHP đích, extensions và ionCube; chuyển pool sang phiên bản mới nhưng giữ nguyên đường socket/vhost Nginx, kiểm tra cú pháp, restart hai PHP-FPM liên quan, xác nhận active và socket. Nếu site có `public/index.php`, KwVPS thử HTTP/PHP qua loopback trước/sau; HTTP 2xx/3xx trước đổi nhưng 5xx hoặc không kết nối sau đổi sẽ thử rollback. Vẫn cần thử các đường dẫn và tính tương thích ứng dụng; site không có `index.php` chỉ được kiểm tra FPM/socket. Không đổi đồng loạt các domain khác.
- **ionCube:** xác minh loader hỗ trợ đúng PHP, kiến trúc và môi trường; tải nguồn chính thức. Bật theo PHP version có thể ảnh hưởng mọi site dùng version đó, phải hiển thị danh sách bị ảnh hưởng. Phân biệt FPM và CLI, không hứa cách ly ionCube theo domain nếu dùng chung runtime.
- **Custom pool:** nano chỉnh bản tạm; kiểm tra cấu hình với binary PHP-FPM đúng phiên bản trước áp dụng. Giữ bản trước sửa. Chặn thay đổi owner/socket làm vượt mô hình cách ly hoặc phải yêu cầu xác nhận rõ. Thoát nano không lưu thì không thay đổi cấu hình thật.

## 7. Nginx — menu chính 6

```text
1. Phục hồi cấu hình theo domain
2. Áp baseline global
3. Kiểm tra cấu hình web server
4. Sửa cấu hình riêng theo domain (nano)
0. Quay lại
```

- **Phục hồi:** chọn site và bản backup hoặc tái tạo từ metadata/template. Giữ SSL, PHP socket, cache, rate limit và Tunnel của site; hiển thị diff và cảnh báo custom config bị thay thế.
- **Baseline global:** bản cấu hình nền có phiên bản; hiện thay đổi và toàn bộ site bị ảnh hưởng. Không ghi đè file người dùng quản lý hoặc lặp lại include Real IP. Không tự chọn thông số “tối ưu” cực đoan cho mọi cấu hình VPS.
- **Kiểm tra:** chạy kiểm tra cú pháp toàn bộ cấu hình, trùng hostname/listen, socket đích và chứng chỉ. Cú pháp đúng không đảm bảo website đúng; sau khi thay cấu hình cần restart, xác nhận Nginx active và thử HTTP/health check đối với site bị ảnh hưởng.
- **Cấu hình riêng:** chọn site theo số; KwVPS mở `/etc/nginx/kwvps-custom/<site-id>/custom.conf` bằng nano. File được include trong server phục vụ ứng dụng ở HTTP hoặc HTTPS, không nằm trong server chuyển hướng HTTP → HTTPS. Có thể thêm `client_max_body_size`, header hoặc location mới; không nhập `server_name`, `root`, `listen`, `include`, PHP socket, TLS hay Real IP vì KwVPS quản lý các phần đó. KwVPS kiểm tra `nginx -t`, restart và hoàn tác nếu lỗi. Snippet đi cùng thao tác đổi domain, đưa site vào vùng giữ/phục hồi và backup cấu hình domain. Khi đổi domain, snippet còn chứa tên miền hoặc site ID cũ sẽ bị từ chối để bạn sửa trước. Nếu vhost đã sửa tay, KwVPS hiện diff với vhost mẫu để bạn xem, yêu cầu xác nhận chuyển sang mẫu và mở nano để đưa các directive cần giữ vào snippet. Bản vhost cũ được lưu root-only; nếu vhost không thể nhận diện an toàn hoặc đang có FastCGI cache, KwVPS từ chối chuyển tự động.

Ghi cấu hình theo giao dịch: lưu trước → chuẩn bị → kiểm tra cú pháp → restart → xác nhận dịch vụ active và health check site khi phù hợp → hoàn tác cấu hình nếu lỗi. Restart có thể gây gián đoạn ngắn; nên thực hiện trong khung bảo trì với site quan trọng. Không để một menu ghi trực tiếp đè file của menu khác.

## 8. Fail2ban — menu chính 7

```text
1. Trạng thái và danh sách jail
2. Xem IP bị khóa
3. Khóa IP thủ công
4. Mở khóa IP
0. Quay lại
```

Chọn jail trước khi xem/ban/unban. Hiển thị IP, jail, lý do, thời hạn và backend thực thi (UFW hoặc Cloudflare nếu đã cấu hình). IP không còn trong một jail vẫn có thể bị chặn bởi jail khác, UFW hoặc Cloudflare.

Validate IPv4/IPv6, cảnh báo IP quản trị và allowlist, không tự thêm IP Cloudflare vào danh sách chặn do hiểu sai log. Unban chỉ gỡ rule thuộc backend/jail đã chọn, không xóa mọi chính sách bảo mật của IP đó.

Đối với SSH kết nối trực tiếp, firewall tại VPS có tác dụng. Đối với HTTP sau Cloudflare, IP TCP ở origin là proxy nên ban visitor IP bằng UFW không chặn request proxy đó; cần hành động ở Nginx hoặc Cloudflare. Module antiDDoS ở mục 19 dùng quy tắc này.

## 9. Tiện ích — menu chính 8

```text
1. Cài/kiểm tra quyền phpMyAdmin
2. phpMyAdmin theo site
3. phpMyAdmin admin tất cả DB
0. Quay lại
```

Bản 0.39 đã nâng lên VPS thử nghiệm. Mục 1 mô phỏng gói Ubuntu rồi mới cài sau xác nhận; không `chmod 777` hoặc đổi quyền đệ quy mã phpMyAdmin do dpkg quản lý. Cấu hình riêng của KwVPS từ chối MariaDB root và tài khoản không mật khẩu.

- **Kết nối từ PuTTY:** trong Connection → SSH → Tunnels, điền Source port `9080`, Destination `127.0.0.1:9080`, chọn Local → Add, rồi kết nối lại. Mở `http://127.0.0.1:9080` trên chính máy tính. Kết nối HTTP chỉ đi qua đường hầm SSH; không mở UFW port 9080, không dùng URL public.
- **Theo site:** chọn site theo danh sách đánh số; menu hiện tên DB/user KwVPS quản lý. Đăng nhập bằng user/mật khẩu DB đã tạo cho site. Quyền đọc/ghi thực tế do GRANT của MariaDB quyết định, không chỉ do giao diện hiển thị.
- **Admin tất cả DB:** tạo `kwvps_admin@localhost` với mật khẩu riêng và quyền toàn bộ database nhưng không có GRANT OPTION; không dùng root qua web. Có thể đổi mật khẩu qua menu; ký tự hiện lúc nhập nhưng không được KwVPS in lại. Chỉ tạo sau xác nhận `y/N`; không đặt mật khẩu vào URL hoặc lưu trong cấu hình KwVPS.
- phpMyAdmin không được cài khi chỉ xem URL. Không công khai mặc định trên mọi domain hoặc lưu session trong source site. Tài khoản admin đã được thử tạo/đăng nhập/xóa trên VPS lab; chưa kiểm thử trình duyệt qua PuTTY của người dùng. Không dùng trên VPS chứa website quan trọng.

## 10. Cron — menu chính 9

```text
1. Quản lý crontab chung
2. Custom crontab (nano)
0. Quay lại
```

**Crontab chung** là danh sách tác vụ KwVPS quản lý; phân biệt root, system cron và user cron. Cho phép xem/thêm/sửa/bật/tắt/xóa với lịch, user thực thi, lệnh, working directory, log và múi giờ. Hiện lịch chạy dự kiến, kiểm tra đường dẫn, quyền và chống chạy chồng nếu cần.

**Custom:** chọn rõ crontab của user nào; lưu bản cũ, chỉnh bản tạm bằng nano, kiểm tra cú pháp trước cài lại. Không ghi đè crontab hiện hữu bằng danh sách rỗng và không tự nhận quản lý tác vụ của phần mềm khác.

Cron PHP phải trỏ đến đúng PHP CLI version site cần. Đổi PHP ở menu 5 phải phát hiện cron liên quan và đề nghị cập nhật; không sửa chuỗi mù. Gia hạn SSL hoặc lịch backup chỉ được tạo bởi module chủ quản, menu cron gọi tới module đó để chỉnh.

## 11. Cache — menu chính 10

```text
1. Xóa cache domain
2. Quản lý cache domain
3. Quản lý Redis
4. Quản lý FastCGI cache
0. Quay lại
```

Đã chuẩn hóa mục FastCGI thành số 4 thay cho số 5 bị bỏ cách trong danh sách yêu cầu.

- **Xóa cache domain:** chọn site và lớp cache cần xóa; hiện phạm vi chính xác. Không mặc định xóa cache Cloudflare vì chưa nằm trong chức năng này. Không xóa cả thư mục cache dùng chung hay Redis FLUSHALL.
- **Cache domain:** trạng thái bật/tắt, TTL, loại nội dung/đường dẫn/cookie bypass. Không cache giỏ hàng, checkout, tài khoản, nội dung cá nhân hóa, request có Authorization hoặc dữ liệu riêng khi chưa chứng minh an toàn.
- **Redis:** trạng thái, version, RAM, giới hạn bộ nhớ, chính sách eviction và liên kết site. Mặc định local socket/loopback, không public. Redis database index không phải ranh giới bảo mật mạnh; cần ACL/key prefix hoặc instance riêng theo mức cách ly. Purge theo site phải biết namespace và không phá session/queue dùng chung.

Bản thử `0.40.0-dev` đã có xem trạng thái/PING, cài gói Redis từ Ubuntu sau mô phỏng và `y/N`, và restart sau `y/N`. Khi cài phải xác minh Redis chỉ nghe loopback; không mở firewall. Chưa có cấu hình bộ nhớ, liên kết site hoặc purge Redis. Không dùng `FLUSHALL`/`FLUSHDB` vì có thể phá cache/session của site khác.
- **FastCGI:** cấu hình được gắn site, namespace/path/key riêng, TTL, bypass, kiểm tra HIT/MISS và xóa đúng phạm vi. Chỉ áp dụng cho luồng PHP-FPM phù hợp; không ghi đè proxy cache tùy ý.

Trên VPS lab, mục 4 đã thử bật/tắt cache của site `.test`: chỉ cache PHP 200 của GET/HEAD không query/cookie/Authorization, TTL 5 phút, tối đa 256 MB/site. Request đầu `MISS`, lần sau `HIT`; cookie và query `BYPASS`. Mục 1 chỉ xóa file FastCGI cache của site được chọn, không xóa Redis hay source. Mục 2 chỉ xem trạng thái/dung lượng; mục 4 bật/tắt. Khi tắt, file cache còn để xóa riêng; không tự xóa dữ liệu. Chưa thử trên ứng dụng thật; các trang cá nhân hóa cần xác minh thêm trước khi bật.

Đổi tên miền hoặc clone phải cập nhật định danh cache. Dùng mã site ổn định để tránh trùng zone/key.

## 12. Swap — menu chính 11

```text
1. Xem swap
2. Thêm swap
3. Xóa swap
0. Quay lại
```

- **Xem:** file/partition, kích thước, đang dùng và cấu hình mount lúc khởi động.
- **Thêm:** chọn dung lượng, kiểm tra disk/filesystem hỗ trợ swapfile, quyền file và giới hạn VPS. Không ghi đè file đang tồn tại. Ghi fstab không trùng, xác minh swap hoạt động sau bật.
- **Xóa:** chỉ chọn swap do KwVPS quản lý theo mặc định; kiểm tra RAM có đủ nhận dữ liệu từ swap không. Nếu không đủ thì từ chối, tránh OOM. Chỉ gỡ file/fstab sau swapoff thành công.

Swap không thay RAM thực; không tự đổi swappiness toàn hệ thống nếu chưa có lựa chọn rõ ràng.

## 13. Firewall — menu chính 12

```text
1. Danh sách port đang mở
2. Mở port
3. Khóa port
4. IP bị khóa
5. Khóa IP
6. Mở khóa IP
7. Bật Firewall UFW
8. Tắt Firewall UFW
0. Quay lại
```

UFW là trình quản lý firewall dự kiến duy nhất của KwVPS. Không cài CSF song song. Phát hiện firewall manager khác hoặc luật ngoài quyền quản lý thì báo trước, không reset.

- **Danh sách port:** tách port đang listen, rule cho phép UFW và tình trạng truy cập từ Internet (nếu đã kiểm chứng). Một rule allow không có nghĩa có dịch vụ đang nghe; firewall nhà cung cấp là lớp riêng.
- **Bật UFW:** menu 7 hoặc tự động khi đã xác nhận mở/khóa port; xác minh `/etc/default/ufw` là root-owned, mặc định deny incoming và `IPV6=yes`. Đọc cổng từ cấu hình `sshd -T`, socket systemd (`systemctl show ssh.socket -p Listen`) và cổng phiên SSH hiện tại, đặt rule ALLOW SSH trước khi kích hoạt; hỗ trợ đầy đủ Ubuntu 24.04 ngay cả khi chạy qua `sudo` làm mất biến `$SSH_CONNECTION`. Nếu bảng rule UFW đang trống, tự động chuyển từ `insert 1` sang `allow`/`deny` thông thường để tránh lỗi cú pháp vị trí UFW. Nếu không xác định được đường SSH an toàn thì từ chối bật. Bật UFW có thể chặn các dịch vụ inbound khác; cần kiểm tra danh sách ALLOW và có console cứu hộ. Menu 8 tắt UFW sau xác nhận `y/N`.
- **Mở/khóa port:** nhập port và TCP/UDP rồi xác nhận `y/N`. Khóa thêm rule DENY ưu tiên do KwVPS sở hữu, không xóa rule ALLOW của bên khác; mở gỡ DENY KwVPS và bảo đảm có ALLOW. Không mở công khai 3306 hoặc khóa cổng SSH cấu hình/đang kết nối. Các lựa chọn source IP/CIDR và lý do riêng từng rule chưa triển khai.
- **IP bị khóa:** hiển thị nguồn UFW/Fail2ban/Cloudflare nếu truy vấn được; chỉ danh sách UFW là dữ liệu module này sở hữu trực tiếp. Cloudflare lỗi API phải báo không xác định, không báo “không bị khóa”.
- **Khóa/mở khóa IP:** kiểm tra allowlist và IP quản trị; gọi backend thích hợp, ghi lý do và phạm vi. Mở khóa UFW không hủy ban Fail2ban/Cloudflare.

Cổng 80/443 là tài nguyên toàn VPS, không thể đóng theo một domain bằng UFW trên cùng IP/port. Firewall của nhà cung cấp VPS nằm ngoài KwVPS; cần kiểm tra mọi site trước thay đổi.

## 14. Disk — menu chính 13

```text
1. Kiểm tra disk của domain
2. Tìm các file lớn của domain
0. Quay lại
```

- **Dung lượng:** chọn site; hiện source, log, cache và backup thuộc site thành các mục riêng; DB là con số riêng để không nhầm với thư mục source. Báo dung lượng trống/inode của filesystem liên quan.
- **File lớn:** chọn ngưỡng hoặc top N; chỉ quét vùng site đã xác minh, không theo symlink ra ngoài, giới hạn ảnh hưởng I/O và số kết quả. Hiển thị size/path, không đọc nội dung.
- Cả hai là thao tác đọc, không kèm tự động xóa. File lớn có thể là dữ liệu quan trọng, backup hoặc log đang được tiến trình sử dụng.

## 15. Logs — menu chính 14

```text
1. Logs của domain
2. Logs Nginx
3. Logs PHP
4. Logs database
5. Dọn toàn bộ log
0. Quay lại
```

Chọn nguồn → khoảng thời gian/số dòng → xem gần nhất hoặc theo dõi. Domain dùng access/error log riêng; PHP xác định đúng version và pool; database mặc định error/service log, không bật general query log ghi mọi truy vấn một cách ngầm định.

Giới hạn số dòng, hỗ trợ logrotate/journal, thông báo file không tồn tại khác với “không có lỗi”. Khi chia sẻ phải che token, cookie, Authorization, query nhạy cảm và thông tin cá nhân. Theo dõi log phải bắt Ctrl+C để dừng và thoát KwVPS; không vô tình giết dịch vụ.

Mục **Dọn toàn bộ log** có ba phạm vi: (1) file access/error của site KwVPS trong `/var/log/nginx` và file PHP-FPM trong `/var/log`, (2) bản journal systemd cũ **của toàn VPS**, hoặc (3) cả hai. Menu hiện kế hoạch, dung lượng trước khi dọn và hỏi `y/N`. File log đang mở được làm rỗng nhưng giữ nguyên file/inode để dịch vụ tiếp tục ghi; chỉ các bản xoay vòng đúng mẫu mới bị xóa. Với journal, KwVPS xoay rồi vacuum về khoảng 1 MB bản lưu cũ; journal đang hoạt động và log phát sinh sau đó vẫn còn. Sau khi dọn, menu liệt kê từng thư mục đã xử lý và số file/byte; không xóa bản thân thư mục. Không đụng log Nginx dùng chung, Fail2ban, log site ngoài KwVPS, dữ liệu database hay Cloudflare ban state. Ubuntu vẫn dùng logrotate/journald để giới hạn log lâu dài; nút này chỉ dọn thủ công. Log đã dọn không thể phục hồi nếu không có backup riêng.

## 16. Update — menu chính 15

```text
1. Kiểm tra / cập nhật KwVPS
2. Kiểm tra / cập nhật Ubuntu
3. Cập nhật service
   1. Kiểm tra version service
   2. Xem package service đang chờ update
   3. Cập nhật service package an toàn
   0. Quay lại
4. Cấu hình GitHub repository
0. Quay lại
```

### KwVPS

Nếu đã lưu `owner/repo` công khai, menu đọc GitHub Release mới nhất qua HTTPS, chỉ nhận tag ổn định `vx.y.z` và gói `kwvps-x.y.z.tar.gz` có SHA-256 trong GitHub API. Gói được kiểm tra checksum và thành phần archive trước khi chạy nâng cấp. Nếu chưa cấu hình repo, vẫn có đường gói local root-only tại `/root/kwvps-update`. Bản cũ được giữ ở `/opt/kwvps-previous-*`; không hứa rollback migration dữ liệu. Chưa có repository/release thật nên đường GitHub chưa được thử đầu-cuối.

### Ubuntu

“Cập nhật Ubuntu” làm mới danh mục APT trước khi lập kế hoạch rồi chỉ nâng package của bản đang dùng, **không nâng bản 24.04 sang bản khác**. Nếu nguồn APT lỗi, PHP-FPM candidate đang chờ nâng chưa đạt ngưỡng vá, hoặc kế hoạch định gỡ package, KwVPS dừng. Chờ unattended-upgrades/apt đang chạy; không xóa lock. Thực hiện trong khung bảo trì; không tự reboot. Sau APT, KwVPS kiểm tra `nginx -t`, cú pháp các PHP-FPM trước đó đang chạy và trạng thái active của các dịch vụ được quản lý trước đó đang chạy; không ép restart lần hai vì APT có thể đã restart. Vẫn cần thử website và tự quyết định reboot.

### Service

Kiểm tra: Nginx, từng PHP-FPM version, MariaDB, Redis, Fail2ban, UFW, Cloudflared. Thành phần chưa cài hiển thị “chưa cài”, không tự cài chỉ để xem version. Phân biệt version package đang cài và tiến trình đang chạy.

Mục chỉ xem danh sách chờ update dùng cache APT hiện tại. Khi chọn **áp dụng** cập nhật dịch vụ, menu làm mới danh mục APT, kiểm tra candidate PHP, mô phỏng kế hoạch và hỏi `y/N`. Từ chối kế hoạch gỡ hoặc cài package ngoài danh sách service đã chọn. Sau APT, kiểm tra Nginx/PHP-FPM và trạng thái các dịch vụ trước đó đang chạy, nhưng không ép restart lần hai. “An toàn” chỉ là các rào chắn trước/sau; **không bảo đảm không downtime** vì maintainer scripts có thể restart dịch vụ và package APT không được KwVPS rollback tự động.

Major upgrade MariaDB/PHP và đổi repository cần quy trình riêng, không gộp vào cập nhật package thông thường. Không tự downgrade database để chữa lỗi vì định dạng dữ liệu có thể không tương thích.

## 17. Sao lưu/phục hồi — menu chính 16

```text
1. Backup cấu hình domain
2. Restore cấu hình domain
3. Backup source/code
4. Restore source/code
5. Danh sách backup source/code
6. Danh sách backup cấu hình domain
7. Kiểm tra backup source/code
8. Kiểm tra backup cấu hình domain
0. Quay lại
```

Bản thử `0.18.1-dev` chọn site và bản backup theo số. Từ `0.50.6`, backup cấu hình có site metadata, PHP-FPM pool, Nginx vhost và — nếu site đã lưu Zone ID — một file token Cloudflare riêng mã hóa bằng mật khẩu. Tải về cả archive `.tar.gz`, file `.cf.enc` và hai checksum; mất mật khẩu thì không thể khôi phục token. Restore yêu cầu site hiện hữu cùng ID/domain, cùng PHP và cùng chế độ HTTP/HTTPS; tự backup cấu hình hiện tại, kiểm tra dịch vụ và health check rồi xác minh token/zone với Cloudflare. Chưa có source, DB, cron/cache/Tunnel tùy biến, chứng chỉ/private key trong gói; chưa phải backup chuyển VPS đầy đủ. Bảng phạm vi bên dưới là đặc tả mục tiêu đầy đủ hơn, không nên hiểu là tất cả đã triển khai.

Tên file backup mới: `source-<domain>-YYYYMMDD-HHMMSS[-N].tar.gz` cho source và `config-<domain>-YYYYMMDD-HHMMSS[-N].tar.gz` cho cấu hình; nếu domain quá dài để tạo tên file an toàn, KwVPS dùng site ID. `-N` chỉ xuất hiện khi cần tránh trùng tên. Cả hai archive vẫn có file `.sha256` tương ứng; backup cấu hình có token Cloudflare còn có file phụ `.cf.enc` mã hóa cùng checksum riêng. Khi tải backup cấu hình sang máy khác, giữ đầy đủ các file phụ và mật khẩu mã hóa. Archive có tên kiểu cũ vẫn được liệt kê và phục hồi, không tự đổi tên hoặc xóa khi nâng cấp.

### Phạm vi backup phải rõ

| Loại | Có gì | Không mặc định bao gồm |
|---|---|---|
| Full cấu hình domain | Metadata site, vhost, pool, custom config, cache/rate-limit, cron do KwVPS quản lý, liên kết SSL/Tunnel | Source, dump DB, toàn bộ hệ điều hành, tài nguyên Cloudflare từ xa |
| Source/code | File ứng dụng và metadata quyền trong document root được chọn | DB, Nginx/PHP config, file ngoài root, cache/log trừ khi chọn |
| Export DB | Một file dump `.sql.gz` theo menu DB, không có `.sha256` mới | Source/config |

“Full cấu hình domain” không có nghĩa full website. Muốn khôi phục website hoàn chỉnh phải có cấu hình + source + DB nhất quán. Có thể đề xuất wizard gộp ba loại sau này nhưng không âm thầm thay đổi phạm vi yêu cầu.

Chứng chỉ/private key và file .env có thể chứa bí mật: phải liệt kê, mã hóa backup nếu đưa vào, giới hạn quyền đọc và không đưa lên GitHub. Từ 0.50.6, token Cloudflare riêng của site được lưu trong file backup phụ mã hóa bằng mật khẩu người dùng; token chung/toàn tài khoản và Tunnel token chưa được backup. DNS/Tunnel/rules ở Cloudflare phải kiểm tra và tái liên kết khi restore, không coi bản file local là đã backup toàn bộ tài khoản.

### Backup

Chọn site → chọn phạm vi → xem dung lượng và nơi lưu → xác nhận → tạo manifest gồm version, thời gian, phạm vi, checksum và PHP/DB yêu cầu → kiểm tra archive. Không gom file backup vào chính backup của nó. Hỗ trợ giữ bản ngoài VPS theo cấu hình sau này, có retention rõ; backup cùng ổ không bảo vệ khỏi mất VPS.

Trạng thái triển khai: backup/restore riêng source và backup/restore cấu hình site (metadata/pool/vhost, Zone ID và token site mã hóa nếu đã cấu hình) có checksum, chọn gói theo số. Gói nằm tại `/var/backups/kwvps` quyền root-only. Mật khẩu mã hóa cần đủ mạnh, nên dùng chuỗi ngẫu nhiên dài từ trình quản lý mật khẩu; mất mật khẩu thì không giải mã được token. Export/import DB nằm ở menu DB. Backup website trọn gói nhất quán, các phần cấu hình nâng cao và lưu bản ngoài VPS vẫn chưa triển khai.

### Restore

Chọn bản → xác minh checksum/manifest → kiểm tra PHP và service đích → giải nén vào vùng tạm an toàn, từ chối path traversal/symlink thoát vùng → xem diff/xung đột → backup hiện trạng → xác nhận → khôi phục đúng phạm vi → validate → health check.

Không ghi đè user/UID hoặc owner từ archive một cách mù quáng. Restore cấu hình không tự hạ phiên bản package. Restore source không tự import DB. Nếu cần tính nhất quán với DB đang ghi, dùng chế độ bảo trì/quy trình snapshot nhất quán và báo downtime. Kiểm thử restore thực tế định kỳ quan trọng hơn chỉ kiểm tra archive đọc được.

## 18. Cloudflare Tunnel — menu chính 17

```text
1. Cấu hình Tunnel
2. Trạng thái
3. Restart
4. Log Tunnel
5. Xem version
0. Quay lại
```

- **Chưa cài cloudflared:** mục 1 hiện `1. Cài cloudflared từ kho APT Cloudflare`, `2. Hướng dẫn tạo Tunnel`, `0. Quay lại`. Cài chỉ sau `y/N`, lấy package từ kho chính thức `pkg.cloudflare.com/cloudflared` cho Ubuntu Noble; không tạo service, không đổi DNS/firewall.
- **Đã cài cloudflared:** mục 1 hướng dẫn tạo Tunnel và route; mục 2 chọn site rồi lưu/thay Tunnel token riêng; mục 3 xem trạng thái các connector; mục 4 ghi nhận chế độ Tunnel/DNS của site; mục 5 gỡ connector/token riêng sau khi chuyển route và chọn DNS; mục 6 quản lý connector chung cũ; `0` quay lại. Site mới do KwVPS tạo được ghi nhận `DNS thông thường` (DNS only hoặc đám mây cam). Site cũ chưa có nhãn vẫn có thể hiện `unknown` khi connector đang chạy; đối chiếu route thật rồi chọn chế độ ở mục 4.
- **Tạo Tunnel:** vào Cloudflare Dashboard → Networking → Tunnels → Create Tunnel, tạo Tunnel loại Cloudflared được quản lý trên Cloudflare. Sao chép **riêng Tunnel token**, không dán cả lệnh cài hoặc gửi token qua chat. Trong mục 2, chọn site bằng số rồi dán token; ký tự hiện trong terminal khi nhập nhưng KwVPS không in lại. Token nằm tại `/etc/kwvps/cloudflare/tunnels/<site-id>.token` quyền root-only; service tương ứng là `kwvps-cloudflared-<site-id>.service`. Sau khi service active, menu hỏi `y/N` để ghi nhận Tunnel. Nếu đồng ý, KwVPS tự cập nhật dải Cloudflare Real IP khi thiếu, áp Real IP riêng vào vhost, chạy `nginx -t` và restart Nginx; lỗi sẽ giữ nguyên chế độ site và hoàn tác thay đổi vhost. Cần bản cloudflared từ 2025.4.0 trở lên cho `--token-file`.
- **Phạm vi token:** mỗi site có thể dùng một connector/token riêng, kể cả khi các domain thuộc các tài khoản Cloudflare khác nhau. Một Tunnel trên Cloudflare vẫn có thể phục vụ nhiều route/hostname; có thể giữ connector chung cũ tại mục 6 cho các site đã cấu hình trước đây. KwVPS không tự chuyển route từ connector chung sang connector riêng. API token theo site ở menu Bảo mật/Cloudflare là loại khác, không thay Tunnel token.
- **Sao lưu hiện tại:** backup cấu hình domain chưa chứa Tunnel token/service riêng hoặc route Cloudflare. Giữ token và thông tin route trong kho bí mật riêng khi chuyển VPS; không coi gói backup cấu hình hiện tại là bản chuyển Tunnel đầy đủ.
- **Hostname/route:** trong Tunnel → Routes → Add route → Published application, chọn đúng hostname/site. Site HTTP dùng `http://127.0.0.1:80`; site HTTPS dùng `https://127.0.0.1:443` và đặt Origin Server Name bằng hostname thật để kiểm tra chứng chỉ. Kiểm tra route/DNS trùng và thử hostname từ ngoài trước khi cân nhắc đổi firewall. KwVPS chưa tự tạo route hoặc DNS trên Cloudflare; Tunnel token khác API token ở menu Bảo mật/Cloudflare.
- **Trạng thái:** liệt kê service theo site và connector chung cũ nếu có. Service active chưa chứng minh hostname công khai dùng được; kiểm tra route và truy cập ngoài VPS riêng.
- **Restart/log:** chọn connector theo số. Restart hỏi `y/N` và chỉ tác động connector đã chọn; log hiển thị 100 dòng gần nhất của connector đó. Một connector chung cũ có thể phục vụ nhiều hostname.
- **Version:** xem phiên bản cloudflared đã cài. Cập nhật package ở menu Update.

### Port 80/443

Menu **Cloudflare Tunnel → Inbound 80/443** có `1. Đóng` và `2. Mở`. Nếu UFW đang tắt, KwVPS hiển thị thông báo rõ ràng, tự động bảo vệ đường SSH và kích hoạt UFW sau xác nhận `y/N`. Áp dụng cơ chế fallback linh hoạt cho `ufw insert 1 deny` khi bảng rule UFW đang trống để thao tác không bị gián đoạn. Đóng yêu cầu Tunnel đang active, thêm DENY ưu tiên cho 80/443 thay vì xóa ALLOW của bên khác, rồi chạy thử gia hạn Certbot (`renew --dry-run`) nếu có chứng chỉ HTTP-01 webroot; thất bại sẽ hoàn tác DENY mới. Mở gỡ DENY do KwVPS tạo và bảo đảm ALLOW 80/443, không sửa rule DENY bên ngoài. Tác động áp dụng toàn VPS, không thay đổi firewall của nhà cung cấp. Luôn kiểm tra `ufw status numbered` và đường truy cập sau thao tác.

Tunnel thiết lập kết nối đi ra nên **có thể đóng inbound 80/443** mà Tunnel vẫn hoạt động: `cloudflared` cần kết nối outbound 7844 tới Cloudflare và truy cập Nginx qua local origin. "Không tự đóng 80/443" trong menu nghĩa là KwVPS không thay firewall thay người dùng, **không phải** hai cổng phải mở công khai để Tunnel chạy. Tuy nhiên:

1. Kiểm kê mọi site và phụ thuộc ACME/monitoring/API/webhook trên VPS.
2. Nếu còn site trực tiếp hoặc Cloudflare proxy truyền thống cần origin 80/443 thì giữ luật cần thiết.
3. Nếu tất cả traffic đã chuyển Tunnel và được kiểm tra từ ngoài, đề nghị đóng inbound qua module Firewall sau xác nhận.
4. Không chặn loopback/local service; giữ kết nối outbound/DNS mà cloudflared cần theo tài liệu chính thức lúc triển khai.
5. Trước tắt Tunnel phải kiểm chứng đường truy cập thay thế và TLS, không tắt rồi mới mở lại cổng.

Với site đã ghi nhận chế độ Tunnel, bản sửa đang kiểm thử chèn trust `127.0.0.1` và `::1` vào **vhost của site đó** để Nginx dùng `CF-Connecting-IP` từ cloudflared; site DNS khác không nhận trust loopback. Cấu hình global chỉ tin dải proxy Cloudflare công khai. Tiến trình local truy cập vhost Tunnel qua loopback vẫn có thể giả header, nên cần cách ly origin/ứng dụng không tin cậy; loopback không tự chứng minh nguồn header. Chưa xác minh request thật từ `kenhgamez.cc` trên VPS production.

## 19. Công cụ nâng cao — menu chính 18

```text
1. Bảo mật/Cloudflare
   1. Cập nhật Cloudflare Real IP cho Nginx
   2. Cấu hình antiDDoS theo domain
   3. Bật/tắt Cloudflare Under Attack
   0. Quay lại
0. Quay lại
```

### 19.1. Real IP dùng chung

Mục tiêu: Nginx ghi nhận visitor IP đúng để log/rate limit hoạt động, không dùng IP proxy làm IP khách.

Bản sửa đang kiểm thử giữ file `/etc/nginx/conf.d/kwvps-cloudflare-realip.conf` chỉ chứa dải IPv4/IPv6 proxy Cloudflare công khai. Khi chạy mục Cập nhật Real IP, KwVPS đồng thời rà các site đã đánh dấu Tunnel và chèn lớp trust loopback riêng vào vhost tương ứng, kiểm tra `nginx -t`, restart Nginx và rollback khi lỗi. Đổi chế độ Tunnel/DNS trong menu Tunnel cũng cập nhật lớp này. Mục Real IP không tạo route Tunnel, sửa firewall, bật rate limit hay Under Attack. Chưa áp bản sửa lên VPS production.

- Với proxy Cloudflare truyền thống: tải IPv4/IPv6 từ nguồn chính thức hiện hành, kiểm tra CIDR và tính hợp lý, chỉ trust nguồn đó, dùng CF-Connecting-IP theo kiến trúc đã kiểm chứng.
- Không trust 0.0.0.0/0 hoặc ::/0; client trực tiếp giả header không được thay remote address.
- Cấu hình dùng chung chỉ tạo một lần; mỗi site dùng đúng chế độ ingress. Tunnel có trust boundary riêng như mục 18, không đơn giản thêm public CIDR rồi kết luận xong.
- Cập nhật danh sách nguyên tử, giữ bản tốt cuối cùng khi tải lỗi; không áp dụng danh sách rỗng.
- Nếu danh sách CIDR còn được dùng trong firewall origin-only thì cập nhật có phối hợp, không để một bên dùng danh sách mới một bên dùng danh sách cũ gây gián đoạn.
- Kiểm tra `nginx -t`, restart rồi xác nhận Nginx active; xác minh log bằng request kiểm soát, giữ cả visitor IP và proxy peer ở format log nếu cần điều tra.

### 19.2. AntiDDoS theo domain

Hai bài người dùng cung cấp trình bày chuỗi: Real IP → rate limiting Nginx → log vi phạm → CSF/LFD đẩy IP lên Cloudflare. Menu `kwvps` → `18` Công cụ nâng cao → `1` Bảo mật/Cloudflare → `2` AntiDDoS theo domain hiện tách hai cách: **(1) Nginx local** và **(2) Cloudflare Rate Limiting**. Cách Nginx: chọn site, 5/10/20/50 request/giây hoặc tắt, xác nhận `y/N`; cần Cloudflare Real IP ở mục 1. Vượt ngưỡng trả HTTP 429, burst gấp đôi rate. Trạng thái ở `/etc/kwvps/cloudflare/antiddos/`, cấu hình ở `/etc/nginx/conf.d/kwvps-antiddos.conf`; script kiểm tra `nginx -t`, restart, xác nhận Nginx active và hoàn tác nếu lỗi. Đã thử HTTPS loopback 40 request ở mức 5: 14 lần 200, 26 lần 429; sau thử đã tắt lại.

Cách Cloudflare dùng Rulesets API, đếm mỗi IP tại biên trong cửa sổ 10 giây và block 10 giây khi vượt mức 50/100/200/500 request. Với gói Pro trở lên, điều kiện `http.host` chỉ áp cho hostname đã chọn. Cloudflare **Free** không hỗ trợ điều kiện hostname: menu hiện rõ tên zone, cảnh báo **mọi hostname/subdomain** đều chịu rule và hỏi `y/N` trước khi tạo. Rule toàn zone dùng expression `true`, có state riêng theo Zone ID; tắt rule cũng báo phạm vi toàn zone. Chỉ tạo/xóa rule mang dấu KwVPS, không thay toàn bộ ruleset. Từ `0.50.6`, chức năng yêu cầu token đã lưu cho site tại menu API token với `Zone WAF Read` và `Zone WAF Write` (ngoài quyền Under Attack); token chung/theo zone kiểu cũ không còn được dùng. KwVPS gọi `dry_run=true` trước khi tạo để Cloudflare xác thực cấu hình/quyền/quota mà chưa ghi rule; lỗi hiển thị mã và lý do đã lọc bí mật. Trên VPS thử nghiệm zone `kenhgamez.top` đang Free: dry-run đã đạt HTTP 200 sau khi sửa `kind: zone`; chưa bật rule thật vì người dùng cần chọn mức và xác nhận `y/N`. Không coi mức Cloudflare và mức Nginx là cùng một cơ chế dù cả hai hiển thị req/s tương đương.

Nginx local **không chống bypass origin**: DNS-only hoặc IP origin lộ vẫn có thể bị truy cập trực tiếp. Cloudflare Rate Limiting chặn tại biên và là cơ chế khác. Tùy chọn mới trong `Nginx local` có thể đọc riêng error log của site KwVPS và đẩy IP bị từ chối lặp lại lên Cloudflare IP Access rule: 5 lần/60 giây, block 15 phút, tối đa 5 IP mới/lượt và 100 ban đang hiệu lực/zone. Chỉ kích hoạt sau xác nhận; mặc định tắt. Timer chạy mỗi phút và không đọc lại log cũ khi bật lần đầu. Rule ban theo IP áp dụng **toàn zone**, dù log nguồn là một site. Khi tắt tính năng, ban đang có tự hết hạn sau tối đa 15 phút nếu worker còn token đúng site để xóa; ban từ bản cũ không xác định được site có thể cần xóa thủ công. Chỉ xóa rule có ID đã lưu do KwVPS tạo. Token site cần thêm quyền IP Access rules Read/Write; API Cloudflare hiện liệt kê `Account Firewall Access Rules Read/Edit` cho endpoint này, còn quyền WAF Read/Edit riêng không đủ. Cần thẩm định thực tế phạm vi quyền trên VPS trước khi bật. Token của từng site cấu hình tại `18 → 1 → 4`; Tunnel token không dùng cho WAF. Chức năng này chỉ dành cho traffic không qua Tunnel, cần Cloudflare Real IP đúng, và không thay CSF/UFW. Chưa kiểm thử API ghi IP Access rule trên VPS; không coi là sẵn sàng production.

Site dùng Tunnel vẫn không được bật rate limit local/bridge đẩy IP chỉ vì đã có Real IP: hai cơ chế đó cần kiểm thử và mô hình tin cậy riêng. Site mới mặc định có nhãn DNS; site cũ thiếu nhãn khi `cloudflared.service` đang chạy là **chưa rõ** và bị chặn cho đến khi người dùng đối chiếu route thật trên Dashboard rồi chọn chế độ. Site dùng Tunnel cần tắt local rate limit trước khi đổi chế độ.

Phần nâng cao dự kiến: tích hợp Fail2ban hoặc bộ xử lý tương thích đã kiểm thử, dùng API Cloudflare quyền tối thiểu, thay vì tự cài CSF/LFD chồng chéo UFW/Fail2ban. Các bước dưới đây là định hướng chưa triển khai toàn bộ.

Luồng sử dụng:

1. Chọn domain và xác nhận traffic thực sự đi qua Cloudflare; DNS-only không được coi là đã được proxy bảo vệ.
2. Kiểm tra Real IP. Nếu thiếu thì hiển thị phụ thuộc và gọi đúng module 19.1 sau xác nhận, không tạo cấu hình Real IP thứ hai. Nếu đã đúng thì tái sử dụng.
3. Chọn phạm vi URL: trang chủ, phần còn lại, endpoint nhạy cảm và static. Giữ logic PHP/try_files hiện tại, không chép nguyên proxy_pass của bài vào site PHP-FPM.
4. Nhập rate (request/giây hoặc phút), burst, delay/nodelay, thời gian quan sát và mã phản hồi. Đề xuất 429 cho rate-limit; chưa có ngưỡng mặc định nào được xem là phù hợp mọi site.
5. Khai báo zone riêng theo mã site/phạm vi; limit_req_zone nằm trong http context, không nhét vào server/location. Khóa nhận diện IP dựa trên Real IP đã xác minh.
6. Chọn ngoại lệ có kiểm soát cho webhook/API/monitoring, đăng nhập hoặc thanh toán; tránh ngoại lệ rộng cho phép bỏ qua bảo vệ. Không bỏ query string khỏi cache key toàn site vì có thể trả nhầm dữ liệu.
7. Ưu tiên chế độ quan sát/dry-run nếu bản Nginx hỗ trợ, kiểm tra log trước khi enforce. NAT dùng chung IP có thể khiến khách thật bị hạn chế.
8. Tùy chọn tự ban ở Cloudflare: chọn ngưỡng vi phạm trong cửa sổ thời gian, thời gian ban, allowlist, giới hạn số ban, zone và backend API được hỗ trợ. Tắt mặc định cho đến khi kiểm thử parser và scope.
9. Hiển thị diff/phạm vi → kiểm tra cú pháp → restart → xác nhận service active → health check. Chỉ kiểm thử lượng request có giới hạn trên VPS thử nghiệm thuộc quyền người dùng, không tạo tải tấn công trên production.

Quản lý ban tự động phải lưu rule ID, owner, site/zone, thời điểm hết hạn; xử lý trùng, retry có giới hạn và rate limit API. Nếu API chỉ có scope rộng hơn một hostname phải báo và xin xác nhận, không tự gọi đó là ban riêng domain. Gỡ đúng rule KwVPS tạo, không xóa rule thủ công có sẵn. Nếu API không có TTL native phải có tác vụ gỡ ban và đối soát sau restart; lỗi gỡ phải báo.

Fail2ban đọc log visitor IP đã xác minh, không tin log/header tùy ý và không mặc định “hai lỗi là bot”. Ban visitor IP ở UFW không thay thế ban tại Cloudflare khi kết nối TCP tới origin vẫn từ Cloudflare.

Tắt antiDDoS của một site chỉ gỡ rate-limit/jail/rules do cấu hình đó sở hữu; không tắt Real IP còn được site khác sử dụng. Nginx limit không bảo vệ được VPS trước volumetric attack làm nghẽn đường truyền; cần bảo vệ của nhà cung cấp và hạn chế lộ/truy cập origin khi thích hợp. Không cam kết chặn hết DDoS.

### 19.3. Under Attack

Nếu chưa có API token, vào **Công cụ nâng cao → Bảo mật/Cloudflare → Cấu hình API token → Thêm/thay token theo site**. Chọn site theo số rồi dán token; ký tự sẽ hiện trong terminal khi nhập để bạn kiểm tra, nhưng KwVPS không in lại token sau đó. Chỉ nhập khi màn hình PuTTY không bị chia sẻ hoặc ghi hình. KwVPS xác minh token còn active, dùng chính token đó tìm Zone ID qua API (`Zone Read`), kiểm tra site thuộc zone và chỉ sau đó lưu token cùng Zone ID root-only cho site. Không cần nhập Zone ID khi thêm token hoặc nhập lại token mỗi lần bật/tắt. Mỗi site có thể dùng token thuộc tài khoản Cloudflare khác nhau; token chung/theo zone kiểu cũ không được tự dùng lại, cần cấu hình lại cho từng site. Nếu thiếu token, menu sẽ chỉ đúng mục này.

Bật/tắt Under Attack cần token Cloudflare với `Zone Read`, `Zone Settings Read` và `Zone Settings Edit` cho đúng zone. Không gửi token trong chat hoặc ghi vào repository. Chọn site bằng số; KwVPS dùng Zone ID đã lưu cho site, hoặc tự tìm bằng token site nếu chưa lưu. Mỗi lần vẫn xác minh domain/zone và đọc mức bảo vệ hiện tại; có lựa chọn đổi ID đã lưu. Under Attack tác động **toàn zone**, không chỉ site được chọn. Khi bật, KwVPS lưu mức cũ trong thư mục root-only; khi tắt chỉ khôi phục mức do chính KwVPS đã lưu. Nếu mức bị đổi ngoài KwVPS, menu từ chối ghi đè. Chu trình bật/tắt với cách lưu token theo site mới chưa được kiểm chứng trên VPS thật.

Chọn domain → xác định Cloudflare zone → hiển thị trạng thái hiện tại và scope API → xác nhận → áp dụng → đọc lại xác minh.

Under Attack ở mức zone có thể ảnh hưởng tất cả hostname trong zone, API client, webhook và người dùng thật. Không giả vờ là thao tác một domain riêng lẻ. Nếu cần chỉ áp một hostname, phải dùng cơ chế rule phù hợp API/gói hiện hành và mô tả rõ khác với zone setting.

Lưu giá trị trước khi bật. Khi tắt, khôi phục giá trị trước đó nếu không có thay đổi bên ngoài; nếu dashboard đã đổi thì báo xung đột, không ghi đè mù. Token chỉ được cấp quyền cần thiết trên zone chọn, lưu ngoài source. Không dùng Global API Key làm mặc định.

### 19.4. Những gì không sao chép nguyên từ bài năm 2021

- CIDR Cloudflare phải lấy hiện hành, không hardcode danh sách cũ trong bài.
- Không áp thông tin giá/gói/cache/API năm 2021 như thông tin hiện tại.
- Không cài CSF song song UFW, không copy regex, tham số testing hoặc Global API Key vào hệ thống mới.
- Không restart Nginx nếu không có thay đổi cấu hình; khi có thay đổi, kiểm tra cú pháp trước, restart và xác nhận service active.
- Ngưỡng rate trong bài chỉ minh họa, phần mô tả và ví dụ còn có chỗ khác nhau; không chọn làm mặc định production.
- Các mẫu location/backend phải viết theo stack thực tế và kiểm thử, không sao chép nguyên file cấu hình ví dụ.

## 20. Liên kết chức năng và nguồn cấu hình dùng chung

### 20.1. Nguyên tắc sở hữu

Một chức năng chỉ có một nơi thực thi logic. Các menu khác gọi lại chức năng đó, không chép code hoặc ghi file cấu hình song song.

| Tài nguyên/chức năng | Module chủ quản | Những nơi gọi lại |
|---|---|---|
| Danh sách/mã site, domain, document root | Sites | Tất cả menu theo domain |
| PHP version, pool, socket | PHP | Thêm/đổi/clone site, restore, cron |
| Certificate, ACME account, renewal | SSL | Sites, restore, Tunnel |
| Vhost/baseline, kiểm tra cú pháp/restart/active | Nginx | SSL, PHP, cache, Real IP, antiDDoS, restore |
| Port/IP UFW, dependency check | Firewall | SSH, DB remote, Tunnel, bảo vệ origin |
| Jail và ban có backend cụ thể | Fail2ban | SSH, antiDDoS, danh sách ban tổng hợp |
| Real IP và CIDR Cloudflare | Cloudflare Real IP | AntiDDoS, log, cấu hình origin-only |
| Cloudflare API credentials/client | Tích hợp Cloudflare chung | DNS-01, Under Attack, edge ban, Tunnel nếu dùng API |
| Lịch do một tính năng tạo | Module của tính năng | Cron chỉ hiển thị/chuyển tới nơi chỉnh |
| Version/package update | Update | PHP, Tunnel, inventory |
| Archive/manifest/restore | Backup | Trước đổi/xóa site, cập nhật và sửa cấu hình |

### 20.2. Metadata tối thiểu đề xuất

Mỗi site có mã ổn định, domain/alias, owner/group, document root, PHP version/socket, DB liên kết, SSL provider/challenge/expiry, kiểu ingress, Tunnel/hostname nếu có, cache và rate-limit profile, cron do KwVPS quản lý, đường dẫn log và tham chiếu backup.

Metadata chỉ lưu tham chiếu bí mật, không gom token/mật khẩu vào một file dễ xuất ra. Bí mật lưu tách biệt, quyền tối thiểu. Phân biệt giá trị mong muốn và trạng thái quan sát được; sửa tay ngoài KwVPS phải được phát hiện thay vì bị ghi đè.

Đường dẫn dự kiến, chưa được tạo bởi tài liệu này:

```text
/opt/kwvps/              Mã chương trình theo release
/usr/local/bin/kwvps     Điểm vào menu
/etc/kwvps/              Cấu hình và metadata có quyền hạn chế
/var/lib/kwvps/          Trạng thái, khóa, bản ghi giao dịch
/var/log/kwvps/          Nhật ký thao tác đã che bí mật
/var/backups/kwvps/      Backup mặc định, giới hạn quyền
/var/www/kwvps/<site-id>/ Dữ liệu site được quản lý
```

Khóa thao tác đồng thời theo tài nguyên; global Nginx/UFW có khóa chung. Không để hai phiên menu cùng ghi cấu hình. Trạng thái chỉ đánh dấu thành công sau validate và kiểm tra áp dụng; thất bại lưu đủ thông tin để tiếp tục/khôi phục có kiểm soát.

### 20.3. Ví dụ liên kết bắt buộc

- Bật antiDDoS → kiểm tra/gọi Real IP → tạo rate-limit riêng site → tùy chọn jail/API → kiểm tra cú pháp và restart Nginx một lần cho thay đổi hợp lệ → xác nhận active và health check site.
- Thêm site → gọi PHP tạo pool → Nginx tạo vhost → tùy chọn DB/SSL; lỗi không được xóa tài nguyên đã tồn tại trước đó.
- Đổi PHP → cập nhật pool/socket → phát hiện cron CLI liên quan → thử site; không thay mọi domain.
- Đóng 80/443 → kiểm kê mọi ingress/challenge → báo xung đột → chỉ gọi UFW khi được xác nhận.
- Restore cấu hình → tái liên kết metadata → dùng từng module kiểm tra tương thích, không giải nén đè toàn /etc.
- Đổi domain → cập nhật mapping SSL/cache/Tunnel → chỉ đổi tài nguyên remote sau xác nhận scope.

## 21. Quy trình thực tế, lỗi và nghiệm thu

### 21.1. Tạo website mới

1. Cài KwVPS trên VPS thử nghiệm sạch khi có release.
2. Menu site → thêm domain → chọn PHP riêng → tạo pool/user/vhost.
3. Tạo DB nếu ứng dụng cần; đưa source lên và phân quyền đúng.
4. Chọn DNS trực tiếp, Cloudflare proxy hoặc Tunnel; kiểm tra đường truy cập.
5. Cấp SSL thích hợp và kiểm tra gia hạn.
6. Bật cache/rate-limit sau khi ứng dụng hoạt động đúng; thử các trang đăng nhập/giỏ hàng/API.
7. Tạo bộ backup config/source/DB và thử restore sang site thử khác.

### 21.2. Chuyển sang Tunnel

Tạo Tunnel/route → thử hostname → xác minh IP thật/TLS → kiểm kê các site khác và ACME → xác nhận chính sách firewall → mới đóng port nếu đủ điều kiện. Luôn giữ đường SSH riêng.

### 21.3. Bảng xử lý lỗi

| Hiện tượng | Kiểm tra trước | Không nên làm |
|---|---|---|
| 502 sau đổi PHP | Pool/socket, quyền socket, PHP error log | chmod 777 toàn site |
| SSL cấp thất bại | DNS A/AAAA, challenge, port/Tunnel, giới hạn CA | Lặp cấp production liên tục |
| Khách bị rate limit đồng loạt | Real IP/trust boundary, NAT, rule theo URL | Tăng ban khi chưa xác minh IP |
| Mở khóa nhưng vẫn không vào | UFW, từng jail, Cloudflare, nhà cung cấp | Reset toàn firewall |
| Tunnel active nhưng site lỗi | Ingress hostname, local service, TLS và DNS | Đóng cổng trực tiếp ngay |
| Nginx validate lỗi | File/dòng báo lỗi và bản trước sửa | Restart cưỡng bức |
| DB import lỗi giữa chừng | Log, dung lượng, quyền, trạng thái DB đích | Khẳng định tự rollback được |
| apt đang bị khóa | Tiến trình cập nhật đang chạy | Xóa lock/kill dpkg tùy tiện |

### 21.4. Tiêu chí nghiệm thu trước phát hành

- Cài mới/cài lại trên Ubuntu 24.04; từ chối môi trường không hỗ trợ và LarVPS có sẵn.
- Menu 0/Ctrl+C nhất quán, có giải thích ngoại lệ nano và package operation.
- Header lấy số đo thực, không dùng dữ liệu mẫu.
- Hai site dùng PHP khác nhau hoạt động; đổi một site không ảnh hưởng site kia.
- Mọi thao tác ghi chạy lại không nhân đôi cấu hình/rule; đầu vào domain/path/SQL/user được kiểm tra.
- Nginx/PHP/SSH cấu hình lỗi không được áp dụng; phục hồi cấu hình được kiểm thử.
- SSH đổi port/key-only có phiên đăng nhập mới xác nhận và đường cứu hộ.
- Site direct/proxy/Tunnel hỗn hợp không bị mất truy cập khi xử lý 80/443.
- Real IP đúng cho IPv4/IPv6, direct và Tunnel; header giả từ nguồn không tin cậy không được chấp nhận.
- Cache không rò rỉ dữ liệu giữa site/người dùng, purge không xóa Redis dùng chung.
- Ban/unban phân biệt UFW/Fail2ban/Cloudflare; scope zone/hostname được hiển thị đúng.
- Backup restore config/source/DB kiểm thử riêng và kết hợp, có dữ liệu mẫu đối chiếu.
- Update có kế hoạch downtime/restart và không tự reboot/major upgrade.
- Kiểm thử mất mạng, hết disk, sai quyền, hủy giữa chừng và chạy đồng thời.
- Kiểm tra Bash bằng ShellCheck, định dạng shfmt, kiểm thử hành vi bằng Bats khi code được triển khai; chạy integration trên VPS/VM thật, không chỉ container.
- Kiểm tra repository/log/archive không rò mật khẩu, token, private key.

## 22. Đối chiếu LarVPS và tài liệu tham khảo

### 22.1. Mức độ xác thực LarVPS

- **Đã quan sát:** ảnh menu chính v2.0.299 có Sites, SSL, SSH/AuthKey, DB, PHP, Nginx, Fail2ban, Cron, Cache, Swap, Firewall, Disk, Logs, Update, Backup/Restore, chuyển dữ liệu, Tunnel và công cụ nâng cao, cùng một số mục khác.
- **Do người dùng yêu cầu:** toàn bộ menu con và chức năng chi tiết được triển khai thành đặc tả ở trên.
- **Chưa xác minh:** số menu con LarVPS thực tế, câu hỏi nhập liệu, file cấu hình, hành vi xóa/clone/restore và command nội bộ.
- **Không suy ra:** quyền sao chép mã nguồn LarVPS, khả năng tương thích KwVPS với cấu hình LarVPS, hoặc khả năng chạy KwVPS an toàn trên VPS LarVPS.

Muốn bổ sung “hướng dẫn LarVPS toàn tập đã kiểm chứng”, cần tài liệu chính thức đúng version hoặc ảnh menu con/quy trình từ môi trường thử nghiệm được phép khảo sát. Mỗi mục ghi version, nguồn, thao tác, đầu vào, kết quả và cảnh báo. Không thử các chức năng ghi trên VPS production chỉ để chụp ảnh. Không đưa thông tin khách hàng hoặc bí mật vào tài liệu.

### 22.2. Hai bài đã đọc theo yêu cầu

1. [Chống DDoS bypass CloudFlare bằng CSF — phần 1, 11/07/2021](https://quangtung1123.github.io/2021/07/11/Chong-ddos-bypass-CloudFlare-bang-CSF-p1): giải thích reverse proxy, IP tại origin, bypass cache và ý tưởng rate-limit theo IP thật.
2. [Chống DDoS bypass CloudFlare bằng CSF — phần 2, 12/07/2021](https://quangtung1123.github.io/2021/07/12/Chong-ddos-bypass-CloudFlare-bang-CSF-p2): Real IP, Nginx limit, theo dõi log và CSF/LFD đẩy IP lên Cloudflare.

Đã đọc nội dung hai bài trong quá trình lập tài liệu. Chỉ kế thừa nguyên lý; các lệnh/cấu hình cũ không được coi là đã phù hợp Ubuntu 24.04 hay Cloudflare API hiện tại.

### 22.3. Nguồn chính thức cần đối chiếu khi triển khai

Các liên kết sau là điểm tra cứu, không có nghĩa mọi trang đã được đọc/kiểm chứng trong lần lập tài liệu này:

- [Cloudflare IP ranges](https://www.cloudflare.com/ips/)
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
- [Cloudflare API](https://developers.cloudflare.com/api/)
- [Nginx Real IP](https://nginx.org/en/docs/http/ngx_http_realip_module.html)
- [Nginx request limiting](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html)
- [Let's Encrypt challenge types](https://letsencrypt.org/docs/challenge-types/)
- [Ubuntu Server documentation](https://documentation.ubuntu.com/server/)

### 22.4. Những điểm cần chốt trước khi viết bộ cài

Tên repository/tài khoản GitHub và phương thức xác thực release; PHP versions/repository cho phép; MariaDB version; ACME client/providers; kiến trúc VPS; cách quản lý Tunnel; chính sách endpoint phpMyAdmin; nơi lưu backup ngoài máy và retention. Những thông tin này chưa cản trở việc dùng tài liệu để chia module, nhưng không được tự bịa vào lệnh cài đặt hoặc tuyên bố hỗ trợ.
