import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart';
import 'package:logging/logging.dart';
import 'package:thermion_dart/thermion_dart.dart'
    hide NativeLibrary, Image_decode;
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/bindings/src/thermion_dart_js_interop.g.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_ktx1_bundle.dart';
import 'package:web/web.dart' as web;

void main(List<String> arguments) async {
  Logger.root.onRecord.listen((record) {
    print(record);
  });

  NativeLibrary.initBindings("thermion_dart");

  final canvas =
      document.getElementById("thermion_canvas") as HTMLCanvasElement;
  try {
    canvas.width = canvas.clientWidth;
    canvas.height = canvas.clientHeight;
  } catch (err) {
    print(err.toString());
  }
  final config = FFIFilamentConfig(backend: Backend.OPENGL);

  await FFIFilamentApp.create(config: config);
  await FilamentApp.instance!
      .setClearOptions(1.0, 0.0, 1.0, 1.0, clear: true, clearStencil: 0);

  var swapChain = await FilamentApp.instance!.createHeadlessSwapChain(
      canvas.width, canvas.height,
      hasStencilBuffer: true);
  print(
      "Created headless swapchain with dimensions ${canvas.width} x ${canvas.height}");
  final viewer = ThermionViewerFFI();
  await viewer.initialized;
  await FilamentApp.instance!.register(swapChain, viewer.view);
  await viewer.view.setFrustumCullingEnabled(false);

  await viewer.setViewport(canvas.width, canvas.height);
  await viewer.render();

  final camera = await viewer.getActiveCamera();

  Timer? _resizeTimer;
  late final bg;
  bool isCubemap = false;
  bool hasImage = false;
  int currentFace = 0;

  // ignore: prefer_function_declarations_over_variables
  bool resizing = false;
  // ignore: prefer_function_declarations_over_variables
  final resizer = (int width, int height) async {
    if (resizing) {
      return;
    }
    try {
      resizing = true;
      await viewer.setViewport(width, height);
      final aspect = width / height;
      await camera.setLensProjection(aspect: aspect);

      Thermion_resizeCanvas(width, height);
      canvas.style.width = "${width}px";
      canvas.style.height = "${height}px";

      _resizeTimer?.cancel();
      _resizeTimer = Timer(Duration(milliseconds: 100), () async {
        await viewer.render();
        print("Resized to ${width}x${height} aspect $aspect");
      });
    } catch (err) {
      print("Error resizing : $err");
    } finally {
      resizing = false;
    }
  };

  bg = await viewer.getBackgroundImage();

  // Function to update active button styling
  void updateActiveButton() {
    final buttons = document.querySelectorAll(".cubemap-button");
    for (int i = 0; i < buttons.length; i++) {
      final button = buttons.item(i) as HTMLButtonElement;
      if (i == currentFace) {
        button.className = "cubemap-button active";
      } else {
        button.className = "cubemap-button";
      }
    }
  }

  // Function to update UI state
  void updateUIState() {
    final controls = document.getElementById("cubemap-controls");

    if (hasImage) {
      if (isCubemap) {
        controls?.className = "cubemap-controls visible";
        updateActiveButton();
      } else {
        controls?.className = "cubemap-controls";
      }
    }
  }

  // Function to clear the image
  void clearImage() async {
    hasImage = false;
    isCubemap = false;
    currentFace = 0;

    // Reset background to default color
    await viewer.setBackgroundColor(0, 0, 1, 1);
    await viewer.render();

    updateUIState();
  }

  // ignore: unused_local_variable
  final onFileLoadEvent =
      (FileReader reader, File? selectedFile, Event event) async {
    final JSArrayBuffer buffer = reader.result as JSArrayBuffer;

    // ignore: sdk_version_since
    final uint8Array = JSUint8Array(buffer, 0, selectedFile!.size);

    print(selectedFile.name);

    if (selectedFile.name.endsWith(".ktx")) {
      final ktxBundle = await FFIKtx1Bundle.create(uint8Array.toDart);
      await bg.setImageFromKtxBundle(ktxBundle);
      print("Set background image from KTX1 bundle");
      hasImage = true;
      isCubemap = ktxBundle.isCubemap();
      if (isCubemap) {
        currentFace = 0;
        await bg.setCubemapFace(currentFace);
      }
    } else if (selectedFile.name.endsWith(".ktx2")) {
      final texture = await FilamentApp.instance!.loadKtx2(uint8Array.toDart);
      hasImage = true;
      isCubemap = false;
      await bg.setImageFromTexture(texture);
    }

    updateUIState();
    for (int i = 0; i < 3; i++) {
      await resizer(bg.width!, bg.height!);
      await Future.delayed(Duration(milliseconds: 100));
    }
  };

  // Expose clearImage function to JavaScript
  window.setProperty(
      'clearImage'.toJS,
      () {
        clearImage();
      }.toJS);

  await Future.delayed(Duration(seconds: 1));

  // Expose setCubemapFace function to JavaScript
  window.setProperty(
      'setCubemapFace'.toJS,
      (int faceIndex) {
        if (isCubemap && faceIndex >= 0 && faceIndex < 6) {
          currentFace = faceIndex;
          bg.setCubemapFace(faceIndex).then((_) async {
            updateActiveButton();
            await viewer.render();
          });
        }
      }.toJS);

  window.setProperty(
      'onFileChanged'.toJS,
      (JSObject? file) {
        final dataTransfer =
            file!.getProperty('dataTransfer'.toJS) as JSObject?;
        final files = dataTransfer!.getProperty('files'.toJS) as FileList;

        final selectedFile = files.item(0);
        if (selectedFile != null) {
          final reader = FileReader();
          reader.onload = (Event event) {
            onFileLoadEvent(reader, selectedFile, event);
          }.toJS;
          reader.readAsArrayBuffer(selectedFile);
        }
      }.toJS);

  // Initial UI state
  updateUIState();

}
