import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Se abre ocupando toda el área visible de la pantalla desde el primer
    // frame (equivalente nativo del fix aplicado en Windows en
    // win32_window.cpp): fijar el frame aquí, antes de que la ventana se
    // muestre, evita la misma carrera de repintado que causaba el plugin
    // window_manager si se maximizaba desde Dart después de mostrarla.
    let pantalla = NSScreen.main?.visibleFrame ?? self.frame
    self.setFrame(pantalla, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
