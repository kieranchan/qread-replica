import Flutter
import UIKit

/// 仿真翻页(IOS原生): the reader's page view of the original (`AppleBookPageView` in its Runner, view type
/// `com.newread/apple_book_view`, one channel `com.newread/apple_book_<viewId>` per view). A `UIPageViewController` with the
/// page-curl transition shows pictures of the previous / current / next screen that the Dart side paints and sends; the view
/// reports finished turns (`pageTurned {delta}`), turns it could not make (`blocked {delta}`) and taps (`tap {x, y, width, height}`).
///
/// Channel calls from Dart: `updateCurrentTexture {image}`, `updateOtherTextures {prev?, next?}` (PNG bytes, a missing or null
/// picture = no page in that direction), `setCanGoPrevious {value}`, `setPaperColor {color}` (ARGB), `animateToNext`,
/// `animateToPrevious`. The original moved pixel buffers (`PageTextureEntry`); PNG bytes are simpler and the pictures are small.
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
    imageView.image = image
    imageView.contentMode = .scaleToFill
    imageView.backgroundColor = paper
    imageView.frame = view.bounds
    imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(imageView)
  }

  required init?(coder: NSCoder) {
    return nil
  }
}

final class AppleBookPageView: NSObject, FlutterPlatformView, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
  private let container: UIView
  private let pager: UIPageViewController
  private let channel: FlutterMethodChannel

  /// Pictures of the previous, current and next screen (nil = no page there).
  private var images: [UIImage?] = [nil, nil, nil]
  private var paper: UIColor
  private var animating = false

  init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    let args = arguments as? [String: Any]
    paper = AppleBookPageView.color(args?["paperColor"]) ?? UIColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1)
    container = UIView(frame: frame)
    pager = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal, options: nil)
    channel = FlutterMethodChannel(name: "com.newread/apple_book_\(viewId)", binaryMessenger: messenger)
    super.init()
    container.backgroundColor = paper
    container.clipsToBounds = true
    pager.dataSource = self
    pager.delegate = self
    pager.isDoubleSided = false
    pager.view.backgroundColor = paper
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
    case "updateCurrentTexture":
      images[1] = AppleBookPageView.image(args?["image"])
      reset()
      result(nil)
    case "updateOtherTextures":
      if let a = args {
        if a.keys.contains("prev") { images[0] = AppleBookPageView.image(a["prev"]) }
        if a.keys.contains("next") { images[2] = AppleBookPageView.image(a["next"]) }
      }
      reset()
      result(nil)
    case "setCanGoPrevious":
      if let can = args?["value"] as? Bool, !can { images[0] = nil }
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

  /// Shows the current picture again without animation: the page view controller drops the neighbours it prefetched, so the next
  /// gesture asks the data source again and gets the new pictures.
  private func reset() {
    if animating { return }
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
    let page = AppleBookPage(image: image, slot: slot, paper: paper)
    pager.setViewControllers([page], direction: delta > 0 ? .forward : .reverse, animated: true) { [weak self] finished in
      guard let self = self else { return }
      self.animating = false
      if finished {
        self.turned(to: page)
      } else {
        self.channel.invokeMethod("blocked", arguments: ["delta": delta])
      }
    }
  }

  /// The page in [page] is the current one now: the pictures shift and Dart moves its position (and sends the new neighbours).
  private func turned(to page: AppleBookPage) {
    let delta = page.slot - 1
    if delta == 0 { return }
    if delta > 0 {
      images = [images[1], images[2], nil]
    } else {
      images = [nil, images[0], images[1]]
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
  }

  func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
    animating = false
    guard completed, let current = pageViewController.viewControllers?.first as? AppleBookPage else { return }
    turned(to: current)
  }

  // MARK: - helpers

  private static func image(_ value: Any?) -> UIImage? {
    guard let data = value as? FlutterStandardTypedData else { return nil }
    return UIImage(data: data.data, scale: UIScreen.main.scale)
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
