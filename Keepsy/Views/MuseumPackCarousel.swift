import SwiftUI
import UIKit

/// Hosts a fixed pool of pages. Only UIKit transforms change on animation frames;
/// the home screen and the SceneKit content do not rebuild for every drag sample.
struct MuseumPackCarousel: UIViewControllerRepresentable {
    let packs: [CarouselPack]
    let revealedCards: Set<String>
    @Binding var selectedMuseumId: String
    let onTapActivePack: () -> Void
    let onTapStart: () -> Void

    func makeUIViewController(context: Context) -> MuseumPackCarouselController {
        let controller = MuseumPackCarouselController()
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: MuseumPackCarouselController, context: Context) {
        controller.onSelect = { selectedMuseumId = $0 }
        controller.onTapActivePack = onTapActivePack
        controller.onTapStart = onTapStart
        controller.configure(packs: packs, revealedCards: revealedCards,
                             selectedMuseumId: selectedMuseumId)
    }

    static func dismantleUIViewController(_ controller: MuseumPackCarouselController, coordinator: ()) {
        controller.stop()
    }
}

@MainActor
final class MuseumPackCarouselController: UIViewController, UIGestureRecognizerDelegate {
    var onSelect: ((String) -> Void)?
    var onTapActivePack: (() -> Void)?
    var onTapStart: (() -> Void)?

    private var packs: [CarouselPack] = []
    private var revealedCards: Set<String> = []
    private var pages: [UIHostingController<MuseumPackPage>] = []
    private var slotPacks: [CarouselPack] = []
    private var rendering: [Bool] = []
    private var motion = PackCarouselMotion()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
    }

    func configure(packs: [CarouselPack], revealedCards: Set<String>, selectedMuseumId: String) {
        loadViewIfNeeded()
        let orderChanged = self.packs.map(\.id) != packs.map(\.id)
        let poolChanged = Set(self.packs.map(\.id)) != Set(packs.map(\.id))
        if poolChanged {
            stop()
            for page in pages {
                page.willMove(toParent: nil)
                page.view.removeFromSuperview()
                page.removeFromParent()
            }
            pages.removeAll()
            slotPacks.removeAll()
            rendering.removeAll()
        }
        self.packs = packs
        self.revealedCards = revealedCards
        pan.isEnabled = packs.count > 1

        if poolChanged {
            for slot in 0..<PackCarouselMotion.slotCount(museumCount: packs.count) {
                slotPacks.append(packs[slot % packs.count])
                let page = UIHostingController(rootView: makePage(slot: slot, isScrolling: false))
                page.safeAreaRegions = []
                addChild(page)
                page.view.backgroundColor = .clear
                page.view.isOpaque = false
                page.view.clipsToBounds = false
                view.addSubview(page.view)
                page.didMove(toParent: self)
                pages.append(page)
                rendering.append(false)
            }
        }

        if orderChanged {
            stop()
            motion.reset(to: packs.firstIndex(where: { $0.id == selectedMuseumId }) ?? 0)
        } else if let index = packs.firstIndex(where: { $0.id == selectedMuseumId }) {
            motion.select(index: index, museumCount: packs.count)
        }
        refreshPages()
        layoutPages()
        if motion.isSettling { startDisplayLink() }
    }

    private func makePage(slot: Int, isScrolling: Bool) -> MuseumPackPage {
        MuseumPackPage(
            pack: slotPacks[slot],
            revealedCards: revealedCards,
            isScrolling: isScrolling,
            onTapActivePack: { [weak self] in self?.onTapActivePack?() },
            onTapStart: { [weak self] in self?.onTapStart?() }
        )
    }

    private func refreshPages() {
        for slot in pages.indices {
            pages[slot].rootView = makePage(slot: slot, isScrolling: rendering[slot])
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPages()
    }

    private func layoutPages() {
        let moving = motion.isDragging || motion.isSettling
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for slot in pages.indices {
            // A location update may reorder packs. Keep each scene attached to
            // its pack and change only its physical place in the ring.
            let packIndex = packs.firstIndex(where: { $0.id == slotPacks[slot].id }) ?? 0
            let ringIndex = packIndex + (slot / packs.count) * packs.count
            let distance = PackCarouselMotion.distance(slot: ringIndex, position: motion.position, slotCount: pages.count)
            let magnitude = abs(distance)
            let page = pages[slot].view!
            page.bounds = CGRect(x: 0, y: 0, width: 380, height: 515)
            page.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let scale = 1.25 - min(magnitude, 1) * (1.25 - 0.88)
            let rotation = min(max(distance, -1), 1) * 5 * .pi / 180
            page.transform = CGAffineTransform(translationX: distance * PackCarouselMotion.spacing, y: 0)
                .rotated(by: rotation).scaledBy(x: scale, y: scale)
            page.alpha = magnitude <= 1 ? 1 - magnitude * 0.35 : max(0, 0.65 * (2 - magnitude))
            page.layer.zPosition = 10 - magnitude
            page.isUserInteractionEnabled = magnitude < 0.5 && !moving
            page.accessibilityElementsHidden = magnitude >= 0.5 || moving

            let shouldRender = moving && magnitude < 2
            if rendering[slot] != shouldRender {
                rendering[slot] = shouldRender
                pages[slot].rootView = makePage(slot: slot, isScrolling: shouldRender)
            }
        }
        CATransaction.commit()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = pan.velocity(in: view)
        return packs.count > 1 && abs(velocity.x) > abs(velocity.y)
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view).x
        switch gesture.state {
        case .began:
            stopDisplayLink()
            motion.beginDrag()
            motion.drag(translation: translation)
        case .changed:
            motion.drag(translation: translation)
        case .ended:
            motion.endDrag(translation: translation, velocity: gesture.velocity(in: view).x)
            let index = PackCarouselMotion.wrapped(motion.target, count: packs.count)
            onSelect?(packs[index].id)
            startDisplayLink()
        case .cancelled, .failed:
            motion.cancelDrag()
            startDisplayLink()
        default:
            return
        }
        layoutPages()
    }

    private func startDisplayLink() {
        guard motion.isSettling, displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget(owner: self), selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        lastTimestamp = CACurrentMediaTime()
        displayLink = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = max(0, now - (lastTimestamp ?? link.timestamp))
        lastTimestamp = now
        motion.advance(seconds: dt, slotCount: pages.count)
        layoutPages()
        if !motion.isSettling { stopDisplayLink() }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    func stop() {
        stopDisplayLink()
        motion.reset(to: motion.target)
        layoutPages()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stop()
    }
}

/// CADisplayLink retains its target. A weak forwarding target lets the carousel
/// and all SceneKit pages be released even if it is removed during a settle.
@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var owner: MuseumPackCarouselController?

    init(owner: MuseumPackCarouselController) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else {
            link.invalidate()
            return
        }
        owner.tick(link)
    }
}
