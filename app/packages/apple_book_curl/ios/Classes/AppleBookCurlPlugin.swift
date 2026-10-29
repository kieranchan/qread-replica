import Flutter
import UIKit

/// 仿真翻页(IOS原生): the reader's page view of the original (`AppleBookPageView` in its Runner, view type
/// `com.newread/apple_book_view`, one channel `com.newread/apple_book_<viewId>` per view). A `UIPageViewController` with the
/// page-curl transition shows pictures of the previous / current / next screen that the Dart side paints and sends; the view
/// reports finished turns (`pageTurned {delta}`), turns it could not make (`blocked {delta}`) and taps (`tap {x, y, width, height}`).
///
/// Channel calls from Dart: `updateTextures {prev?, cur?, next?}` (each `{width, height, bytes}` of raw RGBA at the device pixel
/// ratio, or null = no page in that direction; keys left out are unchanged), `setCanGoPrevious {value}`, `setPaperColor {color}`
/// (ARGB), `animateToNext`, `animateToPrevious`. The pictures are wrapped as CGImages without decoding and prepared for display off
/// the main thread, so a curl never waits for an image; the page view controller is reset (to forget prefetched neighbours) only
/// between gestures. Every animation logs its frame count and hitches (`[apple_book] …`, `syslog live -pn Runner`).
public class AppleBookCurlPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(AppleBookViewFactory(messenger: registrar.messenger()), withId: "com.newread/apple_book_view")
  }
}

final class AppleBookViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return AppleBookPageView(frame: frame, viewId: viewId, arguments: args, messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// One screen of the book: a picture, or blank paper.
final class AppleBookPage: UIViewController {
  let imageView = UIImageView()

  /// 0 previous, 1 current, 2 next.
  var slot: Int

  init(image: UIImage?, slot: Int, paper: UIColor) {
    self.slot = slot
    super.init(nibName: nil, bundle: nil)
    view.backgroundColor = paper
    view.isOpaque = true
    imageView.image = image
    imageView.contentMode = .scaleToFill
    imageView.backgroundColor = paper
    imageView.isOpaque = true
    imageView.frame = view.bounds
    imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(imageView)
  }

  required init?(coder: NSCoder) {
    return nil
  }
}

/// Counts frames and hitches of one animation on a display link.
final class FrameMeter {
  private var link: CADisplayLink?
  private var last: CFTimeInterval = 0
  private var start: CFTimeInterval = 0
  private var frames = 0
  private var hitches = 0
  private var worst: CFTimeInterval = 0

  func begin() {
    end(nil)
    frames = 0
    hitches = 0
    worst = 0
    last = 0
    start = CACurrentMediaTime()
    let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
    l.add(to: .main, forMode: .common)
    link = l
  }

  @objc private func tick(_ l: CADisplayLink) {
    if last > 0 {
      let dt = l.timestamp - last
      let expected = l.targetTimestamp - l.timestamp
      frames += 1
      if dt > expected * 1.5 + 0.002 { hitches += 1 }
      if dt > worst { worst = dt }
    }
    last = l.timestamp
  }

  /// Stops and logs (when [label] is given).
  func end(_ label: String?) {
    guard let l = link else { return }
    l.invalidate()
    link = nil
    if let label = label {
      let ms = Int((CACurrentMediaTime() - start) * 1000)
      NSLog("[apple_book] %@: %d frames, %d hitches, worst %.1f ms, %d ms", label, frames, hitches, worst * 1000, ms)
    }
  }
}

final class AppleBookPageView: NSObject, FlutterPlatformView, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
  private let container: UIView
  private let pager: UIPageViewController
  private let channel: FlutterMethodChannel
  private let meter = FrameMeter()

  /// Pictures of the previous, current and next screen (nil = no page there).
  private var images: [UIImage?] = [nil, nil, nil]

  /// Bumped for every new picture of a slot, so that a late preparation of an old one is dropped.
  private var generation: [Int] = [0, 0, 0]
  private var paper: UIColor
  private var animating = false
  private var resetPending = false

  init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    let args = arguments as? [String: Any]
    paper = AppleBookPageView.color(args?["paperColor"]) ?? UIColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1)
    container = UIView(frame: frame)
    pager = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal, options: nil)
    channel = FlutterMethodChannel(name: "com.newread/apple_book_\(viewId)", binaryMessenger: messenger)
    super.init()
    container.backgroundColor = paper
    container.isOpaque = true
    container.clipsToBounds = true
    pager.dataSource = self
    pager.delegate = self
    pager.isDoubleSided = false
    pager.view.backgroundColor = paper
    pager.view.isOpaque = true
    pager.view.frame = container.bounds
    pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(pager.view)
    // the page view controller turns pages on its own taps near the edges; the app decides the tap zones (and the middle opens the
    // menus), so taps go to Dart and only the pan (the finger-following curl) stays with the page view controller
    for recognizer in pager.gestureRecognizers where recognizer is UITapGestureRecognizer {
      recognizer.isEnabled = false
    }
    let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
    container.addGestureRecognizer(tap)
    pager.setViewControllers([AppleBookPage(image: nil, slot: 1, paper: paper)], direction: .forward, animated: false)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func view() -> UIView {
    return container
  }

  // MARK: - channel

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "updateTextures":
      let t0 = CACurrentMediaTime()
      var changed: [String] = []
      for (key, slot) in [("prev", 0), ("cur", 1), ("next", 2)] {
        guard let a = args, a.keys.contains(key) else { continue }
        changed.append(key)
        setImage(AppleBookPageView.image(a[key]), slot: slot)
      }
      reset()
      NSLog("[apple_book] updateTextures %@ in %.1f ms", changed.joined(separator: ","), (CACurrentMediaTime() - t0) * 1000)
      result(nil)
    case "setCanGoPrevious":
      if let can = args?["value"] as? Bool, !can { setImage(nil, slot: 0) }
      reset()
      result(nil)
    case "setPaperColor":
      if let c = AppleBookPageView.color(args?["color"]) {
        paper = c
        container.backgroundColor = c
        pager.view.backgroundColor = c
        reset()
      }
      result(nil)
    case "animateToNext":
      animate(1)
      result(nil)
    case "animateToPrevious":
      animate(-1)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Stores a picture and prepares it for display off the main thread (a bitmap the GPU can take as it is); the current page shows
  /// the raw picture at once and swaps to the prepared one.
  private func setImage(_ image: UIImage?, slot: Int) {
    generation[slot] += 1
    let gen = generation[slot]
    images[slot] = image
    guard let image = image else { return }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let prepared = image.preparingForDisplay() ?? image
      DispatchQueue.main.async {
        guard let self = self, self.generation[slot] == gen else { return }
        self.images[slot] = prepared
        if slot == 1, let current = self.pager.viewControllers?.first as? AppleBookPage, current.slot == 1 {
          current.imageView.image = prepared
        }
      }
    }
  }

  /// Whether the finger is on a page right now (the page view controller's pan).
  private var panning: Bool {
    return pager.gestureRecognizers.contains { ($0 is UIPanGestureRecognizer) && ($0.state == .began || $0.state == .changed) }
  }

  /// Shows the current picture again without animation: the page view controller drops the neighbours it prefetched, so the next
  /// gesture asks the data source again and gets the new pictures. Never during a curl or while the finger is down (deferred).
  private func reset() {
    if animating || panning {
      resetPending = true
      return
    }
    resetPending = false
    let current = (pager.viewControllers?.first as? AppleBookPage) ?? AppleBookPage(image: nil, slot: 1, paper: paper)
    current.slot = 1
    current.imageView.image = images[1]
    current.imageView.backgroundColor = paper
    current.view.backgroundColor = paper
    pager.setViewControllers([current], direction: .forward, animated: false)
  }

  private func animate(_ delta: Int) {
    if animating { return }
    let slot = delta > 0 ? 2 : 0
    guard let image = images[slot] else {
      channel.invokeMethod("blocked", arguments: ["delta": delta])
      return
    }
    animating = true
    meter.begin()
    let page = AppleBookPage(image: image, slot: slot, paper: paper)
    pager.setViewControllers([page], direction: delta > 0 ? .forward : .reverse, animated: true) { [weak self] finished in
      guard let self = self else { return }
      self.animating = false
      self.meter.end(finished ? "tap turn" : "tap turn (cancelled)")
      if finished {
        self.turned(to: page)
      } else {
        self.channel.invokeMethod("blocked", arguments: ["delta": delta])
      }
      if self.resetPending { self.reset() }
    }
  }

  /// The page in [page] is the current one now: the pictures shift and Dart moves its position (and sends the new neighbour).
  private func turned(to page: AppleBookPage) {
    let delta = page.slot - 1
    if delta == 0 { return }
    if delta > 0 {
      images = [images[1], images[2], nil]
      generation = [generation[1], generation[2], generation[2] + 1]
    } else {
      images = [nil, images[0], images[1]]
      generation = [generation[0] + 1, generation[0], generation[1]]
    }
    page.slot = 1
    channel.invokeMethod("pageTurned", arguments: ["delta": delta])
  }

  @objc private func onTap(_ gesture: UITapGestureRecognizer) {
    if animating { return }
    let p = gesture.location(in: container)
    channel.invokeMethod("tap", arguments: [
      "x": Double(p.x), "y": Double(p.y),
      "width": Double(container.bounds.width), "height": Double(container.bounds.height),
    ])
  }

  // MARK: - UIPageViewControllerDataSource / Delegate

  func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
    guard let page = viewController as? AppleBookPage, page.slot == 1, let image = images[0] else { return nil }
    return AppleBookPage(image: image, slot: 0, paper: paper)
  }

  func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
    guard let page = viewController as? AppleBookPage, page.slot == 1, let image = images[2] else { return nil }
    return AppleBookPage(image: image, slot: 2, paper: paper)
  }

  func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
    animating = true
    meter.begin()
  }

  func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
    animating = false
    meter.end(completed ? "curl" : "curl (put back)")
    if completed, let current = pageViewController.viewControllers?.first as? AppleBookPage {
      turned(to: current)
    }
    if resetPending { reset() }
  }

  // MARK: - helpers

  /// A picture message `{width, height, bytes}` (raw RGBA, 8 bits per channel, rows of width * 4 bytes) as an image that references
  /// the bytes without decoding.
  private static func image(_ value: Any?) -> UIImage? {
    guard let m = value as? [String: Any],
          let data = m["bytes"] as? FlutterStandardTypedData,
          let width = (m["width"] as? NSNumber)?.intValue,
          let height = (m["height"] as? NSNumber)?.intValue,
          width > 0, height > 0, data.data.count >= width * height * 4,
          let provider = CGDataProvider(data: data.data as CFData),
          let cg = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }
    return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)
  }

  private static func color(_ value: Any?) -> UIColor? {
    guard let number = value as? NSNumber else { return nil }
    let argb = UInt32(truncatingIfNeeded: number.int64Value)
    return UIColor(
      red: CGFloat((argb >> 16) & 0xff) / 255,
      green: CGFloat((argb >> 8) & 0xff) / 255,
      blue: CGFloat(argb & 0xff) / 255,
      alpha: CGFloat((argb >> 24) & 0xff) / 255)
  }
}
