# Đánh giá RAM/CPU của OpenKey trên macOS

Phạm vi: baseline được đo trên bản fork tại commit `a059011`. Các sửa đổi
CPU/RAM bên dưới đã được áp dụng trong build 2.0.6/build 51; không thay
engine Telex C++.

## Bản đã cài

Đã thay `/Applications/OpenKey.app` bằng 2.0.6/build 51 universal
(arm64 + x86_64), từ commit code `0526299`. App đã khởi chạy. Bundle
build 50 trước đó được giữ làm bản phục hồi ngoài repository;
preferences người dùng không bị thay đổi. File universal có checksum
SHA-256 `e30ab9c1529a79806c1dca1d254646d9590b0fcea047e07edae4f6d076d83fb3`.

Bản tự build có chữ ký ad hoc nên cần bật lại Accessibility cho
`/Applications/OpenKey.app`. Chưa đo được gõ tiếng Việt thật cho tới khi
quyền này được bật; probe hiệu năng bên dưới chạy bằng callback thật và
tap giả lập.

Probe liên kết object Release thật, fake ranh giới tạo tap và gửi phím để
không gõ vào ứng dụng người dùng. Gọi WindowServer vẫn là API thật;
input source khác tiếng Anh, macro, kiểm tra chính tả và smart switch
được tắt để cô lập phép đo. Một lượt đo, không phải benchmark dài hạn:

| Trường hợp | Phím | Lấy danh sách cửa sổ | Wall time | CPU time |
|---|---:|---:|---:|---:|
| 500 chuỗi `as `, workaround autocomplete tắt | 1.500 | 500 | 107.92 ms | 25.20 ms |
| 500 chuỗi `as `, workaround autocomplete bật | 1.500 | 1.000 | 171.81 ms | 46.05 ms |
| Chỉ engine C++, 100.000 chuỗi `as ` | 300.000 | 0 | 10.87 ms | 10.85 ms |

Probe sau sửa dùng cùng object Release, fake ranh giới tap và phép gõ như
trên, chạy ba cặp baseline/sau sửa. Median khi bật workaround: query giảm
từ 1.000 còn 500, wall time từ 167.47 còn 84.78 ms, CPU từ 46.31 còn
23.68 ms (giảm khoảng 49%). Khi tắt workaround, query vẫn 500; CPU median
là 23.83 ms trước và 23.97 ms sau. Engine C++ median lần lượt 10.03 và
10.21 ms CPU cho 300.000 phím. Đây là probe tổng hợp, không phải phép đo
dài hạn hoặc gõ thật. Mức giảm RAM chưa được đo trực tiếp; phần sửa RAM
được xác định từ ownership leak ở nhánh TIS và tài nguyên qua sleep/wake.

Hai dòng đầu là hai cấu hình khác nhau, không phải kết quả trước/sau
một bản tối ưu. Việc tắt workaround làm thay đổi hành vi nên không
đề xuất tự tắt cấu hình hiện tại chỉ để giảm số đo.

## Các sửa đổi đã áp dụng

1. **Giảm công việc trong callback.** Các quyết định workaround dùng
   chung một snapshot Spotlight trong callback. Kiểm tra cấu hình, app
   Spotlight và số thao tác thay chữ trước khi gọi WindowServer. Trong
   probe 500 chuỗi, số query giảm một nửa khi workaround bật. Cache không
   tồn tại qua callback nên trạng thái Spotlight không bị cũ.
2. **Sửa ownership input source bằng Rust.** Nhánh `vOtherLanguage` gọi
   helper Rust nhỏ, không dùng allocator/std. `TISCopy...` được giữ trong
   wrapper RAII và luôn `CFRelease` khi thoát; language array và phần tử
   lấy từ Get API vẫn là dữ liệu mượn, không release. Kết quả không đọc
   được sẽ fail-open như nhánh nguồn null trước đây. Helper giữ đúng phép
   so khớp chính xác `en` của `isLike:@"en"` cũ. Leak xảy ra khi tùy chọn
   tắt OpenKey ở input language khác tiếng Anh được bật; nếu bật, nhánh
   này chạy trên mỗi key down/up.
3. **Dọn tài nguyên khi sleep/wake và init lỗi.** `OpenKeyShutdown`
   giải phóng/null event source và hai backspace events. `stopEventTap`
   dọn run-loop source, tap và gọi shutdown; mọi đường init thất bại cũng
   dọn tài nguyên đã tạo. Khởi tạo lại bắt đầu từ trạng thái sạch.
4. **Lịch sử gõ vẫn giữ nguyên.** Engine lưu các từ của dòng vào
   `_typingStates` để phục hồi khi backspace; chỉ clear khi ngắt dòng,
   điều hướng hoặc tác vụ khác. Dòng cực dài có thể giữ nhiều trạng
   thái. Cần đo riêng rồi mới chọn giới hạn vì giới hạn làm thay đổi
   khả năng phục hồi khi xóa ngược qua nhiều từ.

## Công nghệ phù hợp

- **Rust ở ranh giới ownership, C++ ở engine:** Rust chỉ bao bọc phần
  Core Foundation có lỗi sở hữu cụ thể; engine Telex vẫn C++ vì đã chạy
  khoảng 10 ms/300.000 phím và không có lợi ích đo được khi viết lại.
- **SMAppService.mainApp:** API từ macOS 13 cho đăng ký chính ứng dụng
  chạy cùng máy. Có thể thay helper chỉ dùng để mở app chính; cần xử
  lý đăng ký cũ và quyền Login Items khi chuyển. Lợi ích RAM chưa đo.
- **InputMethodKit:** framework chính thức cho bộ gõ hệ thống, có từ
  macOS 10.5, không phải công nghệ vừa xuất hiện. Cho phép tái sử dụng
  engine C++ và giao tiếp theo session văn bản thay vì dựa hoàn toàn
  vào global event tap/backspace giả lập. Đây là thay đổi kiến trúc:
  phải kiểm tra marked text, underline, phím tắt và tương thích Safari,
  Chrome, VS Code, Telegram trước khi chọn. Chưa có prototype hoặc
  số đo để kết luận nó tiết kiệm hơn OpenKey hiện tại.

Ưu tiên: giảm truy vấn cửa sổ trùng và sửa ownership/teardown trước;
đánh giá InputMethodKit bằng prototype riêng nếu muốn đổi trải nghiệm
bộ gõ. Bản đã cài vẫn là bản phục hồi timeout, không phải bản tối ưu mới.

## Tài liệu chính thức

- [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
- [Core Foundation ownership](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFMemoryMgmt/Concepts/Ownership.html)
- [InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)
- [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)

Quy tắc property TIS (mã ngôn ngữ BCP 47; property mượn từ Get API) và
`NSString isLike:` được đối chiếu trong SDK Xcode:
`Carbon.framework/Frameworks/HIToolbox.framework/Headers/TextInputSources.h`
và `Foundation.framework/Headers/NSScriptWhoseTests.h`.
