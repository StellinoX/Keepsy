import SwiftUI
import SceneKit

fileprivate var cachedCardBackTexture: UIImage?

@available(iOS 14.0, *)
fileprivate func createCardBackTexture() -> UIImage {
    if let cached = cachedCardBackTexture { return cached }
    if let retroImage = UIImage(named: "retro") {
        cachedCardBackTexture = retroImage
        return retroImage
    }
    let size = CGSize(width: 540, height: 780)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2.0
    let renderer = UIGraphicsImageRenderer(size: size, format: format)

    let result = renderer.image { ctx in
        let context = ctx.cgContext
        let cornerRadius: CGFloat = 58 // matches SwiftUI cr = 12/111 * 540

        // 1. Clip to rounded rect
        let clipPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius)
        context.addPath(clipPath.cgPath)
        context.clip()

        // 2. Gradient fill matching SwiftUI cardBackGradient (#2D1C76 to #432B3F)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradientColors = [
            UIColor(red: 0x2D / 255.0, green: 0x1C / 255.0, blue: 0x76 / 255.0, alpha: 1.0).cgColor,
            UIColor(red: 0x43 / 255.0, green: 0x2B / 255.0, blue: 0x3F / 255.0, alpha: 1.0).cgColor
        ]
        let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0.0, 1.0])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])

        // 3. LogoKeepsy centered (same visual as SwiftUI cardBack)
        if let logo = UIImage(named: "LogoKeepsy") {
            let logoSize: CGFloat = 262
            let logoRect = CGRect(
                x: (size.width - logoSize) / 2,
                y: (size.height - logoSize) / 2,
                width: logoSize,
                height: logoSize
            )
            logo.draw(in: logoRect)
        }

        context.resetClip()

        // 4. Gold gradient border matching SwiftUI goldBorder
        let goldColors: [CGColor] = [
            UIColor(red: 0xF5/255.0, green: 0xE4/255.0, blue: 0x80/255.0, alpha: 1.0).cgColor,
            UIColor(red: 0xF1/255.0, green: 0xB4/255.0, blue: 0x0A/255.0, alpha: 1.0).cgColor,
            UIColor(red: 0x9A/255.0, green: 0x6F/255.0, blue: 0x00/255.0, alpha: 1.0).cgColor,
            UIColor(red: 0xF1/255.0, green: 0xB4/255.0, blue: 0x0A/255.0, alpha: 1.0).cgColor,
            UIColor(red: 0xF5/255.0, green: 0xE4/255.0, blue: 0x80/255.0, alpha: 1.0).cgColor,
        ]
        let goldGradient = CGGradient(colorsSpace: colorSpace, colors: goldColors as CFArray,
                                      locations: [0.0, 0.25, 0.5, 0.75, 1.0])!

        let borderLineWidth: CGFloat = 10
        let borderInset = borderLineWidth / 2
        let borderPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: borderInset, dy: borderInset),
            cornerRadius: cornerRadius - borderInset
        )
        context.saveGState()
        context.setLineWidth(borderLineWidth)
        context.addPath(borderPath.cgPath)
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(goldGradient,
                                   start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: size.width, y: size.height),
                                   options: [])
        context.restoreGState()
    }
    cachedCardBackTexture = result
    return result
}

fileprivate var cachedTornMask: UIImage?

@available(iOS 14.0, *)
fileprivate func createTornMask() -> UIImage {
    if let cached = cachedTornMask { return cached }
    let texSize = CGSize(width: 256, height: 256)
    let renderer = UIGraphicsImageRenderer(size: texSize)
    
    let result = renderer.image { ctx in
        // Background is Black (Body)
        UIColor.black.setFill()
        ctx.fill(CGRect(origin: .zero, size: texSize))
        
        // Draw Flap (Red) with a wavy tear line
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        
        // Start of tear line
        let startY = 60.0
        path.addLine(to: CGPoint(x: 0, y: startY))
        
        for x in stride(from: 0.0, through: Double(texSize.width), by: 5.0) {
            let y = startY + sin(x * 0.1) * 6.0 + cos(x * 0.05) * 3.0
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: texSize.width, y: 0))
        path.close()
        
        // Apply blur shadow for smooth edge
        ctx.cgContext.setShadow(offset: .zero, blur: 10.0, color: UIColor.red.cgColor)
        UIColor.red.setFill()
        path.fill()
    }
    cachedTornMask = result
    return result
}

@available(iOS 16.0, *)
@MainActor
fileprivate func createCardFrontTexture(name: String) -> UIImage {
    let title = CardDatabase.cleanedArtworkName(name)
    let index = CardDatabase.allArtworkNames.firstIndex(of: name)
    let isRevealed = CardDatabase.getRevealedCards().contains(name)
    let borderGrad = CardDatabase.borderGradientFor(name: name)
    
    // Ensure the image is loaded into the memory cache first so ImageRenderer draws it
    if CardDatabase.imageCache.object(forKey: name as NSString) == nil {
        if let image = CardDatabase.localImage(for: name) {
            CardDatabase.imageCache.setObject(image, forKey: name as NSString)
        }
    }
    
    let cardView = ArtworkCardFrontView(
        name: name,
        title: title,
        cardIndex: index,
        width: 540,
        height: 818,
        isRevealed: isRevealed,
        goldBorder: borderGrad,
        showCheckmark: false
    )
    
    let renderer = ImageRenderer(content: cardView)
    renderer.scale = 2.0
    
    return renderer.uiImage ?? UIImage()
}

fileprivate var cachedHorizontalFlareTexture: UIImage?

@available(iOS 14.0, *)
fileprivate func createHorizontalFlareTexture() -> UIImage {
    if let cached = cachedHorizontalFlareTexture { return cached }
    let size = CGSize(width: 512, height: 128)
    let renderer = UIGraphicsImageRenderer(size: size)
    
    let result = renderer.image { ctx in
        let context = ctx.cgContext
        context.clear(CGRect(origin: .zero, size: size))
        
        let colors = [
            UIColor.clear.cgColor,
            UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.35).cgColor, // Cyan
            UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 0.55).cgColor, // Gold/Yellow
            UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.35).cgColor, // Cyan
            UIColor.clear.cgColor
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let glowGradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 0.3, 0.5, 0.7, 1.0])!
        
        let glowRect = CGRect(x: 0, y: 16, width: size.width, height: 96)
        context.saveGState()
        context.clip(to: glowRect)
        context.drawLinearGradient(glowGradient, start: CGPoint(x: 0, y: glowRect.minY), end: CGPoint(x: 0, y: glowRect.maxY), options: [])
        context.restoreGState()
        
        let coreColors = [
            UIColor.clear.cgColor,
            UIColor.white.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor
        ]
        let coreGradient = CGGradient(colorsSpace: colorSpace, colors: coreColors as CFArray, locations: [0.0, 0.25, 0.75, 1.0])!
        
        let coreRect = CGRect(x: 0, y: 56, width: size.width, height: 16)
        context.saveGState()
        context.clip(to: coreRect)
        context.drawLinearGradient(coreGradient, start: CGPoint(x: 0, y: coreRect.minY), end: CGPoint(x: 0, y: coreRect.maxY), options: [])
        context.restoreGState()
    }
    cachedHorizontalFlareTexture = result
    return result
}

@available(iOS 14.0, *)
fileprivate func createTearParticleSystem() -> SCNParticleSystem {
    let ps = SCNParticleSystem()
    ps.loops = false
    ps.birthRate = 500
    ps.emissionDuration = 0.22
    ps.particleLifeSpan = 0.65
    ps.particleLifeSpanVariation = 0.2
    
    // Emitter Shape: Horizontal bar matching packet tear width
    let emitterShape = SCNBox(width: 5.5, height: 0.1, length: 0.1, chamferRadius: 0.0)
    ps.emitterShape = emitterShape
    ps.emittingDirection = SCNVector3(0, 0, 1) // Shoot out towards camera
    ps.spreadingAngle = 35.0
    ps.particleVelocity = 3.5
    ps.particleVelocityVariation = 1.5
    
    ps.particleSize = 0.07
    ps.particleSizeVariation = 0.03
    ps.particleColor = UIColor(red: 1.0, green: 0.82, blue: 0.4, alpha: 1.0) // Gold
    ps.particleColorVariation = SCNVector4(0.08, 0.08, 0.15, 0.0)
    
    let sizeController = SCNParticlePropertyController(animation: CAKeyframeAnimation(keyPath: "size"))
    if let sizeAnim = sizeController.animation as? CAKeyframeAnimation {
        sizeAnim.values = [1.0, 0.7, 0.0]
        sizeAnim.keyTimes = [0.0, 0.5, 1.0]
    }
    
    let opacityController = SCNParticlePropertyController(animation: CAKeyframeAnimation(keyPath: "opacity"))
    if let opacityAnim = opacityController.animation as? CAKeyframeAnimation {
        opacityAnim.values = [1.0, 0.8, 0.0]
        opacityAnim.keyTimes = [0.0, 0.6, 1.0]
    }
    
    ps.propertyControllers = [
        .size: sizeController,
        .opacity: opacityController
    ]
    
    ps.blendMode = .additive
    return ps
}

@available(iOS 14.0, *)
fileprivate func createCenterBlastParticleSystem() -> SCNParticleSystem {
    let ps = SCNParticleSystem()
    ps.loops = false
    ps.birthRate = 600
    ps.emissionDuration = 0.12
    ps.particleLifeSpan = 0.85
    ps.particleLifeSpanVariation = 0.3
    
    ps.emitterShape = SCNSphere(radius: 0.15)
    ps.particleVelocity = 7.0
    ps.particleVelocityVariation = 3.0
    
    ps.particleSize = 0.11
    ps.particleSizeVariation = 0.05
    ps.particleColor = UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 1.0) // Electric Cyan
    
    let sizeController = SCNParticlePropertyController(animation: CAKeyframeAnimation(keyPath: "size"))
    if let sizeAnim = sizeController.animation as? CAKeyframeAnimation {
        sizeAnim.values = [1.0, 0.0]
        sizeAnim.keyTimes = [0.0, 1.0]
    }
    
    let opacityController = SCNParticlePropertyController(animation: CAKeyframeAnimation(keyPath: "opacity"))
    if let opacityAnim = opacityController.animation as? CAKeyframeAnimation {
        opacityAnim.values = [1.0, 0.0]
        opacityAnim.keyTimes = [0.0, 1.0]
    }
    
    ps.propertyControllers = [
        .size: sizeController,
        .opacity: opacityController
    ]
    
    ps.blendMode = .additive
    return ps
}

@available(iOS 14.0, *)
public struct SceneKitPacketView: UIViewRepresentable {
    var onOpen: (() -> Void)?
    var onTearComplete: (() -> Void)?
    var interactive: Bool
    var isTorn: Bool
    var museumId: String?
    var packetImageName: String?
    var firstCardName: String?
    var isFirstCardRevealed: Bool
    var tearMaskImage: UIImage?
    
    public init(interactive: Bool = true, isTorn: Bool = false, museumId: String? = nil, packetImageName: String? = nil, firstCardName: String? = nil, isFirstCardRevealed: Bool = false, tearMaskImage: UIImage? = nil, onTearComplete: (() -> Void)? = nil, onOpen: (() -> Void)? = nil) {
        self.interactive = interactive
        self.isTorn = isTorn
        self.museumId = museumId
        self.packetImageName = packetImageName
        self.firstCardName = firstCardName
        self.isFirstCardRevealed = isFirstCardRevealed
        self.tearMaskImage = tearMaskImage
        self.onTearComplete = onTearComplete
        self.onOpen = onOpen
    }
    
    public func fillBackground(context: Context) {}
    
    public func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor.clear // Make background clear to show gradient underneath
        view.isUserInteractionEnabled = interactive
        view.rendersContinuously = false
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        
        if interactive {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(PacketCoordinator.handlePan(_:)))
            view.addGestureRecognizer(pan)
        }
        
        context.coordinator.scnView = view
        return view
    }
    
    public func updateUIView(_ uiView: SCNView, context: Context) {
        // Applica i cambiamenti di isTorn e della maschera se la vista SwiftUI viene aggiornata senza essere ricreata
        context.coordinator.firstCardName = firstCardName
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        if isTorn {
            let tornMask = tearMaskImage ?? createTornMask()
            context.coordinator.maskProp.contents = tornMask
            
            let uniforms = SCNVector4(0, 0, 0, 10.0) // fingerX far right
            context.coordinator.bodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            context.coordinator.backBodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            
            context.coordinator.topGroupNode.isHidden = true
            context.coordinator.backFlapNode.isHidden = true
            context.coordinator.topSealNode.isHidden = true
            
            if !interactive {
                context.coordinator.deckContainer.position = SCNVector3(0, 0.95, -0.05)
                context.coordinator.deckContainer.scale = SCNVector3(0.75, 0.75, 0.75)
            } else {
                context.coordinator.deckContainer.position = SCNVector3(0, 1.2, -0.05)
                context.coordinator.deckContainer.scale = SCNVector3(1.0, 1.0, 1.0)
            }
            context.coordinator.deckContainer.isHidden = false
            context.coordinator.tiltContainerNode.eulerAngles = SCNVector3(0, 0, 0)
        } else {
            context.coordinator.maskProp.contents = UIColor.black
            let uniforms = SCNVector4(0, 0, 0, -10.0)
            context.coordinator.bodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            context.coordinator.backBodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            context.coordinator.flapNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            context.coordinator.backFlapNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            
            context.coordinator.topGroupNode.isHidden = false
            context.coordinator.backFlapNode.isHidden = false
            context.coordinator.topSealNode.isHidden = false
            
            context.coordinator.deckContainer.position = SCNVector3(0, 0, -0.12)
            if !interactive {
                context.coordinator.deckContainer.scale = SCNVector3(0.8, 0.8, 0.8)
            } else {
                context.coordinator.deckContainer.scale = SCNVector3(1.0, 1.0, 1.0)
            }
            context.coordinator.deckContainer.isHidden = true
            context.coordinator.tiltContainerNode.eulerAngles = SCNVector3(0, 0, -0.06)
        }
        SCNTransaction.commit()
    }
    
    public func makeCoordinator() -> PacketCoordinator {
        return PacketCoordinator(interactive: interactive, isTorn: isTorn, museumId: museumId, packetImageName: packetImageName, firstCardName: firstCardName, isFirstCardRevealed: isFirstCardRevealed, tearMaskImage: tearMaskImage, onTearComplete: onTearComplete, onOpen: onOpen)
    }
}

@MainActor
public class PacketCoordinator: NSObject {
    var scene: SCNScene
    weak var scnView: SCNView?
    var interactive: Bool
    var museumId: String?
    var firstCardName: String?
    
    let bodyNode: SCNNode
    let flapNode: SCNNode
    let deckContainer: SCNNode
    var cardNodes: [SCNNode] = []
    
    // Back face of the 3D packet (cuts dynamically with offset)
    let backBodyNode: SCNNode
    let backFlapNode: SCNNode
    
    // Straight top and bottom seals
    let topSealNode: SCNNode
    let bottomSealNode: SCNNode
    
    // Groups to keep pieces perfectly glued together when animating
    let tiltContainerNode: SCNNode
    let topGroupNode: SCNNode
    let bottomGroupNode: SCNNode
    let flareNode: SCNNode
    
    var touchPoints: [CGPoint] = []
    let maskProp = SCNMaterialProperty(contents: UIColor.black)
    var onOpen: (() -> Void)?
    var onTearComplete: (() -> Void)?
    var lastMaskImage: UIImage?
    var lastHapticFingerX: Float = -10.0
    var packetImageName: String?
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func artworkImageDownloaded(_ notification: Notification) {
        guard let firstCardName = self.firstCardName,
              let name = notification.userInfo?["internalName"] as? String,
              name == firstCardName else { return }
        
        if #available(iOS 16.0, *) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            if self.cardNodes.count > 0 {
                self.cardNodes[0].geometry?.firstMaterial?.diffuse.contents = createCardFrontTexture(name: firstCardName)
            }
            SCNTransaction.commit()
        }
    }
    
    public init(interactive: Bool = true, isTorn: Bool = false, museumId: String? = nil, packetImageName: String? = nil, firstCardName: String? = nil, isFirstCardRevealed: Bool = false, tearMaskImage: UIImage? = nil, onTearComplete: (() -> Void)? = nil, onOpen: (() -> Void)? = nil) {
        self.interactive = interactive
        self.museumId = museumId
        self.packetImageName = packetImageName
        self.firstCardName = firstCardName
        self.onTearComplete = onTearComplete
        self.onOpen = onOpen
        scene = SCNScene()
        
        // 1. Camera Setup
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 15)
        scene.rootNode.addChildNode(cameraNode)
        
        // 2. Lighting (PBR environment and Premium Studio Lights)
        scene.lightingEnvironment.contents = UIColor(white: 0.8, alpha: 1.0)
        scene.lightingEnvironment.intensity = 1.2
        
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 150
        scene.rootNode.addChildNode(ambientLight)
        
        let dirLight = SCNNode()
        dirLight.light = SCNLight()
        dirLight.light?.type = .directional
        dirLight.light?.intensity = 800
        dirLight.light?.castsShadow = true
        dirLight.position = SCNVector3(x: 2, y: 8, z: 10)
        dirLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(dirLight)
        
        let blueLight = SCNNode()
        blueLight.light = SCNLight()
        blueLight.light?.type = .omni
        blueLight.light?.color = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)
        blueLight.light?.intensity = 500
        blueLight.position = SCNVector3(x: -8, y: 5, z: 5)
        scene.rootNode.addChildNode(blueLight)
        
        let warmLight = SCNNode()
        warmLight.light = SCNLight()
        warmLight.light?.type = .omni
        warmLight.light?.color = UIColor(red: 1.0, green: 0.7, blue: 0.4, alpha: 1)
        warmLight.light?.intensity = 400
        warmLight.position = SCNVector3(x: 8, y: -2, z: 8)
        scene.rootNode.addChildNode(warmLight)
        
        // 3. Packet Geometry (High-quality 3D Plane with massive tessellation)
        let width: CGFloat = 6.1 // Extra width for side rounding
        let height: CGFloat = 9.0
        let packetGeo = SCNPlane(width: width, height: height)
        packetGeo.cornerRadius = 0.1
        packetGeo.widthSegmentCount = 100 // Needed for smooth side curl
        packetGeo.heightSegmentCount = 100
        
        // Material (Dark Foil PBR)
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        let finalImageName = packetImageName ?? "packet"
        if let userImg = UIImage(named: finalImageName) ?? UIImage(named: "Apri_pacchetto_Copy_14_3x") ?? UIImage(named: "uffizi_pacchetto") ?? UIImage(named: "packet") {
            mat.diffuse.contents = userImg
        } else {
            mat.diffuse.contents = UIColor(white: 0.12, alpha: 1.0)
        }
        mat.metalness.contents = 0.6
        mat.roughness.contents = 0.4
        mat.isDoubleSided = true
        packetGeo.materials = [mat]
        
        bodyNode = SCNNode(geometry: packetGeo.copy() as? SCNGeometry)
        flapNode = SCNNode(geometry: packetGeo.copy() as? SCNGeometry)
        
        // Bind dynamic mask texture
        bodyNode.geometry?.setValue(maskProp, forKey: "maskTex")
        flapNode.geometry?.setValue(maskProp, forKey: "maskTex")
        
        // Initial fingerX is far left, so no curl
        let initialUniforms = SCNVector4(x: 0, y: 0, z: 0, w: -10)
        bodyNode.geometry?.setValue(NSValue(scnVector4: initialUniforms), forKey: "customData")
        flapNode.geometry?.setValue(NSValue(scnVector4: initialUniforms), forKey: "customData")
        
        // 4. Custom Shaders
        let geometryShaderBase = """
        #pragma arguments
        texture2d<float, access::sample> maskTex;
        float4 customData; // w = fingerX
        
        #pragma varyings
        float edgeGlow;
        float2 rawUV; // Pass exact UV to fragment shader for pixel-perfect sampling
        
        #pragma body
        constexpr sampler maskSampler(coord::normalized, address::clamp_to_edge, filter::linear);
        float fingerX = customData.w;
        
        // SCNPlane UVs: (0,0) is bottom-left, (1,1) is top-right.
        float2 sampleUV = _geometry.texcoords[0];
        out.rawUV = sampleUV; // Pass to fragment shader
        
        float m = maskTex.sample(maskSampler, sampleUV).r;
        
        // m=1 is Flap(Top), m=0 is Body(Bottom). Edge is at m=0.5
        float isCutEdge = smoothstep(0.0, 1.0, 1.0 - abs(m - 0.5) * 2.0);
        
        // Only curl if we are to the left of the finger!
        float curlActive = 1.0 - smoothstep(fingerX - 0.2, fingerX + 0.1, _geometry.position.x);
        float curl = isCutEdge * curlActive;
        
        // --- GLOW EFFECT ---
        float distFromFinger = max(0.0, fingerX - _geometry.position.x);
        float glowFactor = exp(-distFromFinger * 4.0); // Fades exponentially behind the finger
        out.edgeGlow = curl * glowFactor;
        """
        
        let sideRoundingShader = """
        // --- SEAMLESS SIDE ROUNDING ---
        float r = 0.125;
        float edgeStart = 2.85;
        float absX = abs(_geometry.position.x);
        if (absX > edgeStart) {
            float dx = absX - edgeStart;
            float theta = min(dx / r, 1.5708); // Max 90 degrees
            float signX = sign(_geometry.position.x);
            _geometry.position.x = signX * (edgeStart + r * sin(theta));
            _geometry.position.z -= r * (1.0 - cos(theta)); // Curls backward to meet the back
        }
        """
        
        // Body (bottom part) always curls down at the edge, no internal mesh stretching
        let bodyGeometryShader = geometryShaderBase + """
        if (curl > 0.01) {
            _geometry.position.z += curl * 0.15;
            _geometry.position.y -= curl * 0.06;
        }
        """ + sideRoundingShader
        
        // Flap (top part) always curls up at the edge
        let flapGeometryShader = geometryShaderBase + """
        if (curl > 0.01) {
            _geometry.position.z += curl * 0.15;
            _geometry.position.y += curl * 0.06;
        }
        """ + sideRoundingShader
        
        let foilShader = """
        // --- FOIL WRINKLES & CRIMPS (Procedural Normal Mapping) ---
        float2 uv = _surface.diffuseTexcoord;
        float3 n = _surface.normal;
        
        float isCrimp = step(0.88, uv.y) + step(uv.y, 0.12);
        float ridge = sin(uv.y * 350.0) * 0.4;
        n.y += isCrimp * ridge;
        
        float wrinkleX = sin(uv.y * 20.0 + uv.x * 10.0) * cos(uv.x * 35.0) * 0.12;
        float wrinkleY = sin(uv.x * 25.0 - uv.y * 15.0) * 0.12;
        n.x += wrinkleX * (1.0 - isCrimp);
        n.y += wrinkleY * (1.0 - isCrimp);
        
        _surface.normal = normalize(n);
        """
        
        let bodySurface = """
        #pragma arguments
        texture2d<float, access::sample> maskTex;
        
        #pragma transparent
        #pragma body
        // Sample texture per-pixel for perfectly crisp edges without staircases
        constexpr sampler maskSamplerFrag(coord::normalized, address::clamp_to_edge, filter::linear);
        float mFrag = maskTex.sample(maskSamplerFrag, in.rawUV).r;
        
        // Smooth Anti-Aliasing (Blend the edge instead of hard discard)
        float alpha = smoothstep(0.53, 0.47, mFrag) * _surface.diffuse.a;
        if (alpha <= 0.01) { discard_fragment(); }
        _surface.transparent.a = alpha;
        """ + foilShader + """
        
        // Add Premium Glow at the cut edge (Laser / Sparks effect)
        _surface.emission = float4(1.0, 0.4, 0.0, 1.0) * in.edgeGlow * 8.0;
        """
        
        let flapSurface = """
        #pragma arguments
        texture2d<float, access::sample> maskTex;
        
        #pragma transparent
        #pragma body
        // Sample texture per-pixel for perfectly crisp edges
        constexpr sampler maskSamplerFrag(coord::normalized, address::clamp_to_edge, filter::linear);
        float mFrag = maskTex.sample(maskSamplerFrag, in.rawUV).r;
        
        // Smooth Anti-Aliasing (Blend the edge instead of hard discard)
        float alpha = smoothstep(0.47, 0.53, mFrag) * _surface.diffuse.a;
        if (alpha <= 0.01) { discard_fragment(); }
        _surface.transparent.a = alpha;
        """ + foilShader + """
        
        // Add Premium Glow at the cut edge (Laser / Sparks effect)
        // Add Premium Glow at the cut edge (Laser / Sparks effect)
        _surface.emission = float4(1.0, 0.4, 0.0, 1.0) * in.edgeGlow * 8.0;
        """
        
        // ==========================================
        // === BACK FOIL SHADERS (Reverse Curl) ===
        // ==========================================
        
        let backGeometryShaderBase = """
        #pragma arguments
        texture2d<float, access::sample> maskTex;
        float4 customData; // w = fingerX
        
        #pragma varyings
        float2 rawUV;
        
        #pragma body
        constexpr sampler maskSampler(coord::normalized, address::clamp_to_edge, filter::linear);
        float fingerX = customData.w;
        
        float2 sampleUV = _geometry.texcoords[0];
        // OFFSET for depth illusion! The back cuts slightly to the right of the front.
        sampleUV.x += 0.02; 
        out.rawUV = sampleUV;
        
        float m = maskTex.sample(maskSampler, sampleUV).r;
        float isCutEdge = smoothstep(0.0, 1.0, 1.0 - abs(m - 0.5) * 2.0);
        float curlActive = 1.0 - smoothstep(fingerX - 0.2, fingerX + 0.1, _geometry.position.x);
        float curl = isCutEdge * curlActive;
        """
        
        let backSideRoundingShader = """
        // --- SEAMLESS SIDE ROUNDING (BACK) ---
        float r = 0.125;
        float edgeStart = 2.85;
        float absX = abs(_geometry.position.x);
        if (absX > edgeStart) {
            float dx = absX - edgeStart;
            float theta = min(dx / r, 1.5708); // Max 90 degrees
            float signX = sign(_geometry.position.x);
            _geometry.position.x = signX * (edgeStart + r * sin(theta));
            _geometry.position.z += r * (1.0 - cos(theta)); // Curls forward to meet the front
        }
        """
        
        let backBodyGeometryShader = backGeometryShaderBase + """
        if (curl > 0.01) {
            _geometry.position.z -= curl * 0.15; // Curls BACKWARD
            _geometry.position.y -= curl * 0.06;
        }
        """ + backSideRoundingShader
        
        let backFlapGeometryShader = backGeometryShaderBase + """
        if (curl > 0.01) {
            _geometry.position.z -= curl * 0.15; // Curls BACKWARD
            _geometry.position.y += curl * 0.06;
        }
        """ + backSideRoundingShader
        
        let backBodySurface = """
        #pragma arguments
        texture2d<float, access::sample> maskTex;
        
        #pragma transparent
        #pragma body
        constexpr sampler maskSamplerFrag(coord::normalized, address::clamp_to_edge, filter::linear);
        float mFrag = maskTex.sample(maskSamplerFrag, in.rawUV).r;
        
        float alpha = smoothstep(0.53, 0.47, mFrag) * _surface.diffuse.a;
        if (alpha <= 0.01) { discard_fragment(); }
        _surface.transparent.a = alpha;
        """
        
        let backFlapSurface = """
        #pragma arguments
        texture2d<float, access::sample> maskTex;
        
        #pragma transparent
        #pragma body
        constexpr sampler maskSamplerFrag(coord::normalized, address::clamp_to_edge, filter::linear);
        float mFrag = maskTex.sample(maskSamplerFrag, in.rawUV).r;
        
        float alpha = smoothstep(0.47, 0.53, mFrag) * _surface.diffuse.a;
        if (alpha <= 0.01) { discard_fragment(); }
        _surface.transparent.a = alpha;
        """
        
        bodyNode.geometry?.shaderModifiers = [.geometry: bodyGeometryShader, .surface: bodySurface]
        flapNode.geometry?.shaderModifiers = [.geometry: flapGeometryShader, .surface: flapSurface]
        
        // --- RIGID GROUPS & TILT CONTAINER ---
        tiltContainerNode = SCNNode()
        scene.rootNode.addChildNode(tiltContainerNode)
        
        topGroupNode = SCNNode()
        bottomGroupNode = SCNNode()
        tiltContainerNode.addChildNode(topGroupNode)
        tiltContainerNode.addChildNode(bottomGroupNode)
        
        bottomGroupNode.addChildNode(bodyNode)
        topGroupNode.addChildNode(flapNode)
        
        // 5. Back face of the 3D packet — uses a discard shader with UV offset for depth.
        // Also applies reverse-curl geometry so the packet opens like a physical pouch!
        let backMat = SCNMaterial()
        backMat.lightingModel = .physicallyBased
        if let userImg = UIImage(named: finalImageName) ?? UIImage(named: "Apri_pacchetto_Copy_14_3x") ?? UIImage(named: "uffizi_pacchetto") ?? UIImage(named: "packet") {
            backMat.diffuse.contents = userImg
            // Multiply with dark gray to make the back dark/metallic like the inside of a pouch
            backMat.multiply.contents = UIColor(white: 0.15, alpha: 1.0)
        } else {
            backMat.diffuse.contents = UIColor(white: 0.1, alpha: 1.0)
        }
        backMat.metalness.contents = 0.8
        backMat.roughness.contents = 0.5
        backMat.isDoubleSided = true
        
        let backGeo = SCNPlane(width: 6.1, height: 9.0)
        backGeo.cornerRadius = 0.1
        backGeo.widthSegmentCount = 100 // High tessellation for smooth curling
        backGeo.heightSegmentCount = 100
        backGeo.materials = [backMat]
        
        // Initialize the back nodes with independent geometry copies
        backBodyNode = SCNNode(geometry: backGeo.copy() as? SCNGeometry)
        backFlapNode = SCNNode(geometry: backGeo.copy() as? SCNGeometry)
        
        // Place behind the card
        backBodyNode.position = SCNVector3(0, 0, -0.05)
        backFlapNode.position = SCNVector3(0, 0, -0.05)
        
        bottomGroupNode.addChildNode(backBodyNode)
        topGroupNode.addChildNode(backFlapNode)
        
        // --- STRAIGHT TOP AND BOTTOM SEALS ---
        let sideMatDark = SCNMaterial()
        sideMatDark.lightingModel = .physicallyBased
        sideMatDark.diffuse.contents = UIColor(white: 0.08, alpha: 1.0)
        sideMatDark.metalness.contents = 0.8
        sideMatDark.roughness.contents = 0.5
        
        let sealGeo = SCNPlane(width: 5.29, height: 0.25)
        sealGeo.materials = [sideMatDark]
        
        topSealNode = SCNNode(geometry: sealGeo)
        topSealNode.position = SCNVector3(0, 4.5, -0.125)
        topSealNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        topGroupNode.addChildNode(topSealNode)
        
        bottomSealNode = SCNNode(geometry: sealGeo)
        bottomSealNode.position = SCNVector3(0, -4.5, -0.125)
        bottomSealNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        bottomGroupNode.addChildNode(bottomSealNode)
        
        // Bind mask and customData to back planes
        backBodyNode.geometry?.setValue(maskProp, forKey: "maskTex")
        backFlapNode.geometry?.setValue(maskProp, forKey: "maskTex")
        backBodyNode.geometry?.setValue(NSValue(scnVector4: initialUniforms), forKey: "customData")
        backFlapNode.geometry?.setValue(NSValue(scnVector4: initialUniforms), forKey: "customData")
        
        // Re-apply modifiers to the new geometries
        backBodyNode.geometry?.shaderModifiers = [.geometry: backBodyGeometryShader, .surface: backBodySurface]
        backFlapNode.geometry?.shaderModifiers = [.geometry: backFlapGeometryShader, .surface: backFlapSurface]
        
        // 6. Card inside the 3D packet
        let cardGeo = SCNPlane(width: 5.15, height: 7.8) // Aspect ratio matches 111x168
        cardGeo.cornerRadius = 0.15
        let cardMat = SCNMaterial()
        cardMat.lightingModel = .physicallyBased
        cardMat.diffuse.contents = createCardBackTexture()
        cardMat.emission.contents = UIColor.black // Remove emission so it looks like a real card
        cardGeo.materials = [cardMat]
        
        deckContainer = SCNNode()
        deckContainer.position = SCNVector3(0, 0, -0.12) // Between front and back
        deckContainer.isHidden = !isTorn // Hidden by default if not torn yet to prevent showing from underneath
        if !interactive {
            deckContainer.scale = SCNVector3(0.75, 0.75, 0.75)
        }
        tiltContainerNode.addChildNode(deckContainer)
        
        for i in 0..<5 {
            let cNode = SCNNode(geometry: cardGeo)
            // Stack them slightly on the Z axis
            cNode.position = SCNVector3(0, 0, Float(i) * -0.01)
            deckContainer.addChildNode(cNode)
            cardNodes.append(cNode)
        }
        
        // Premium tilt (apply to container so everything moves perfectly along its local axis)
        let tilt = SCNVector3(0, 0, -0.06)
        tiltContainerNode.eulerAngles = tilt
        
        // Initialize Horizontal Lens Flare Node
        let flareGeo = SCNPlane(width: 30.0, height: 1.2)
        let flareMat = SCNMaterial()
        flareMat.lightingModel = .constant
        flareMat.diffuse.contents = createHorizontalFlareTexture()
        flareMat.blendMode = .screen
        flareMat.readsFromDepthBuffer = false
        flareMat.writesToDepthBuffer = false
        flareGeo.materials = [flareMat]
        
        flareNode = SCNNode(geometry: flareGeo)
        flareNode.position = SCNVector3(0, 3.0, 0.3) // Slightly in front of packet and cards
        flareNode.opacity = 0.0
        tiltContainerNode.addChildNode(flareNode)
        
        if isTorn {
            topGroupNode.isHidden = true
            backFlapNode.isHidden = true
            topSealNode.isHidden = true
            
            let tornMask = tearMaskImage ?? createTornMask()
            maskProp.contents = tornMask
            
            let uniforms = SCNVector4(0, 0, 0, 10.0) // fingerX far right
            bodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            backBodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            
            // Move deck container up so it sticks out of the packet
            if !interactive {
                deckContainer.position = SCNVector3(0, 0.95, -0.05)
            } else {
                deckContainer.position = SCNVector3(0, 1.2, -0.05)
            }
            
            // Remove Z-tilt rotation when the packet is already torn, keeping it centered and straight
            tiltContainerNode.eulerAngles = SCNVector3(0, 0, 0)
            
            if let firstCardName = firstCardName {
                let uniqueCardGeo = cardGeo.copy() as! SCNPlane
                let uniqueCardMat = SCNMaterial()
                uniqueCardMat.lightingModel = .physicallyBased
                uniqueCardMat.diffuse.contents = createCardFrontTexture(name: firstCardName)
                uniqueCardMat.emission.contents = UIColor.black
                uniqueCardGeo.materials = [uniqueCardMat]
                cardNodes[0].geometry = uniqueCardGeo
            }
        }
        
        super.init()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(artworkImageDownloaded(_:)),
            name: NSNotification.Name("ArtworkImageDownloaded"),
            object: nil
        )
    }
    
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = scnView else { return }
        let location = gesture.location(in: view)
        
        switch gesture.state {
        case .began:
            let local = screenToLocal(point: location, view: view)
            // Only allow the tear to start if the user touches the upper half of the packet
            if local.y > 1.0 {
                touchPoints = [location]
                lastHapticFingerX = -10.0
            }
        case .changed:
            if !touchPoints.isEmpty {
                touchPoints.append(location)
                updateMask()
            }
        case .ended, .cancelled:
            if !touchPoints.isEmpty {
                finalizeCut()
                touchPoints.removeAll()
            }
        default:
            break
        }
    }
    
    private func screenToLocal(point: CGPoint, view: SCNView) -> SCNVector3 {
        // Create a ray from near clip plane to far clip plane
        let pNear = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0.0))
        let pFar = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1.0))
        
        // Convert the ray to the node's local coordinate space
        let localNear = bodyNode.convertPosition(pNear, from: nil)
        let localFar = bodyNode.convertPosition(pFar, from: nil)
        
        // Intersect the ray with the Z=0 plane (the surface of our SCNPlane)
        let dz = localFar.z - localNear.z
        if abs(dz) > 0.0001 {
            let t = -localNear.z / dz
            let localX = localNear.x + t * (localFar.x - localNear.x)
            let localY = localNear.y + t * (localFar.y - localNear.y)
            return SCNVector3(localX, localY, 0)
        }
        
        return localNear
    }
    
    private func updateMask() {
        guard !touchPoints.isEmpty, let view = scnView else { return }
        
        // PERFORMANCE FIX: Dropped resolution to 256x256 (16x faster generation!).
        // Because the Metal Fragment Shader uses bilinear filtering (filter::linear)
        // and evaluates smoothstep per-pixel, the final cut will still look infinitely sharp and HD!
        let texSize = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: texSize)
        
        // Convert screen touches to local UV texture coordinates
        let uvPoints = touchPoints.map { pt -> CGPoint in
            var local = screenToLocal(point: pt, view: view)
            
            // LIMIT CUT ZONE: Allow freeform wavy tearing, but restricted to a specific horizontal "tear strip" band.
            // We allow the Y coordinate to freely move between 2.6 and 3.4 (just below the seal).
            // If the user goes outside this band, the cut will smoothly clamp to the edges of the strip.
            local.y = max(2.6, min(3.4, local.y))
            
            let u = (CGFloat(local.x) + 3.0) / 6.0
            // UIKit Y is 0 at top. Local Y is +4.5 at top.
            let v = 1.0 - (CGFloat(local.y) + 4.5) / 9.0
            return CGPoint(x: max(0, min(texSize.width, u * texSize.width)),
                           y: max(0, min(texSize.height, v * texSize.height)))
        }
        
        let maskImage = renderer.image { ctx in
            // Background is Black (Body)
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: texSize))
            
            // Draw Flap (Red) with mathematical spline smoothing (QuadCurves)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: 0)) // Top left
            path.addLine(to: CGPoint(x: 0, y: uvPoints[0].y)) // Start of cut
            path.addLine(to: uvPoints[0])
            
            for i in 1..<uvPoints.count {
                let current = uvPoints[i]
                let previous = uvPoints[i - 1]
                let midPoint = CGPoint(x: (current.x + previous.x) / 2, y: (current.y + previous.y) / 2)
                
                if i == 1 {
                    path.addLine(to: midPoint)
                } else {
                    path.addQuadCurve(to: midPoint, controlPoint: previous)
                }
            }
            path.addLine(to: uvPoints.last!)
            
            // Extend the flap boundary horizontally to the right edge
            let lastPt = uvPoints.last!
            path.addLine(to: CGPoint(x: texSize.width, y: lastPt.y))
            path.addLine(to: CGPoint(x: texSize.width, y: 0)) // Top right
            path.close()
            
            // Apply a slight blur/shadow to the edge so the mask.r has a smooth gradient (0.0 to 1.0)
            // Reduced blur to 10.0 to match the 256x256 resolution and eliminate CPU lag
            ctx.cgContext.setShadow(offset: .zero, blur: 10.0, color: UIColor.red.cgColor)
            UIColor.red.setFill()
            path.fill()
        }
        
        // Update the material mask dynamically!
        maskProp.contents = maskImage
        self.lastMaskImage = maskImage
        
        // Pass fingerX to the shader to activate the curl ONLY where the finger has passed
        let fingerX = Float(screenToLocal(point: touchPoints.last!, view: view).x)
        let uniforms = SCNVector4(0, 0, 0, fingerX)
        
        // Trigger a haptic tick when the finger cuts further to the right
        if lastHapticFingerX == -10.0 {
            lastHapticFingerX = fingerX
        } else if fingerX > lastHapticFingerX + 0.45 {
            HapticManager.shared.triggerSelection()
            lastHapticFingerX = fingerX
        }
        
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.0
        bodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
        flapNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
        backBodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
        backFlapNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
        SCNTransaction.commit()
    }
    
    private func finalizeCut() {
        guard let lastPt = touchPoints.last, let view = scnView else { return }
        let start = touchPoints.first!
        let dx = lastPt.x - start.x
        
        // If cut spans across at least 35% of the screen width
        if dx > view.bounds.width * 0.35 {
            let maskToSave = self.lastMaskImage
            let city = self.museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
            let key = "activePackTearMask_\(city)"
            DispatchQueue.global(qos: .utility).async {
                if let lastMask = maskToSave, let pngData = lastMask.pngData() {
                    print("DEBUG: Tear mask successfully saved to UserDefaults, size: \(pngData.count) bytes")
                    UserDefaults.standard.set(pngData, forKey: key)
                } else {
                    print("DEBUG: Tear mask failed to convert to pngData or lastMask is nil")
                }
            }
            
            // Force curl across the whole packet before dropping
            let uniforms = SCNVector4(0, 0, 0, 10.0) // fingerX far right
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.0
            bodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            flapNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            backBodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            backFlapNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            SCNTransaction.commit()
            
            // Trigger haptic success vibration
            HapticManager.shared.triggerNotification(type: .success)
            
            // Trigger callbacks
            self.onTearComplete?()
            
            animateOpen()
        } else {
            // Cut failed (too short), reset mask
            maskProp.contents = UIColor.black
            let uniforms = SCNVector4(0, 0, 0, -10.0)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            bodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            flapNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            backBodyNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            backFlapNode.geometry?.setValue(NSValue(scnVector4: uniforms), forKey: "customData")
            SCNTransaction.commit()
        }
    }
    
    private func animateOpen() {
        // Keep rendering active during animation to prevent dropped frames.
        scnView?.rendersContinuously = true
        
        // Show the deck cards since we are now opening the packet
        deckContainer.isHidden = false

        // === FLARE ===
        flareNode.opacity = 0.0
        flareNode.scale = SCNVector3(1.0, 0.1, 1.0)
        let flashDuration = 0.12
        let fadeDuration = 0.6
        let fadeIn = SCNAction.fadeIn(duration: 0.08)
        let scaleYUp = SCNAction.customAction(duration: flashDuration) { node, elapsedTime in
            node.scale = SCNVector3(1.0, 0.1 + Float(elapsedTime / flashDuration) * 1.7, 1.0)
        }
        let fadeOut = SCNAction.fadeOut(duration: fadeDuration)
        let scaleYDown = SCNAction.customAction(duration: fadeDuration) { node, elapsedTime in
            node.scale = SCNVector3(1.0, 1.8 - Float(elapsedTime / fadeDuration) * 1.78, 1.0)
        }
        flareNode.runAction(SCNAction.sequence([
            SCNAction.group([fadeIn, scaleYUp]),
            SCNAction.wait(duration: 0.08),
            SCNAction.group([fadeOut, scaleYDown]),
            SCNAction.removeFromParentNode()
        ]))

        // === PARTICLES ===
        let particleNode = SCNNode()
        particleNode.position = SCNVector3(0, 3.0, 0.2)
        particleNode.addParticleSystem(createTearParticleSystem())
        particleNode.addParticleSystem(createCenterBlastParticleSystem())
        tiltContainerNode.addChildNode(particleNode)
        particleNode.runAction(SCNAction.sequence([
            SCNAction.wait(duration: 1.5),
            SCNAction.removeFromParentNode()
        ]))

        // === TOP GROUP: small flap flicks up and away quickly ===
        let flyUp = SCNAction.moveBy(x: 2.5, y: 14.0, z: 1.0, duration: 0.9)
        flyUp.timingMode = .easeOut
        let topRotate = SCNAction.rotateBy(x: 2.2, y: 1.2, z: -1.0, duration: 0.9)
        topRotate.timingMode = .linear
        let topScale = SCNAction.scale(to: 0.3, duration: 0.9)
        topScale.timingMode = .easeIn
        topGroupNode.runAction(SCNAction.group([flyUp, topRotate, topScale]))

        // === BOTTOM GROUP: falls DOWN and BACKWARD so it recedes behind the deck ===
        // z: -4 moves it away from camera — deck cards stay in front, no clip-through.
        let bodyDownAction = SCNAction.moveBy(x: 0, y: -18.0, z: -4.0, duration: 1.3)
        bodyDownAction.timingMode = .easeIn
        bottomGroupNode.runAction(bodyDownAction)

        // === DECK: slide up out of the falling packet and present — single smooth motion ===
        let wait = SCNAction.wait(duration: 0.1)

        // Slide up slightly and bring closer to camera (no scaling down) - stay centered at y: 0.0 to match SwiftUI cards final placement
        let slideUp = SCNAction.move(to: SCNVector3(0, 0.0, 0.8), duration: 0.8)
        slideUp.timingMode = .easeOut
        
        let straighten = SCNAction.rotateTo(x: 0, y: 0, z: 0.06, duration: 0.8)
        straighten.timingMode = .easeOut
        
        let presentGroup = SCNAction.group([slideUp, straighten])

        deckContainer.runAction(SCNAction.sequence([wait, presentGroup]))

        // Notify after deck reaches center.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            self.onOpen?()
        }

        // Drop back to on-demand rendering once animations finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            self.scnView?.rendersContinuously = false
        }
    }
}

// SwiftUI Preview Fallback
struct SceneKitPacketView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.13).ignoresSafeArea()
            SceneKitPacketView(onOpen: {
                print("Opened!")
            })
            .ignoresSafeArea()
        }
    }
}
