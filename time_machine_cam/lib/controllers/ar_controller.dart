import 'dart:async';
import 'package:ar_flutter_plugin_engine/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_engine/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_engine/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_engine/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_engine/models/ar_node.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:time_machine_cam/services/transformation_service.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:vector_math/vector_math_64.dart';

class ARController {
  ARController({
    this.databaseService,
    this.networkService,
  });

  final DatabaseService? databaseService;
  final NetworkService? networkService;
  final Map<String, ARNode> _nodes = {};
  final Map<String, Picture> _pictures = {};

  TransformationService? transformationService;
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARLocationManager? arLocationManager;
  StreamSubscription? _eventSubscription;

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    arSessionManager?.dispose();
    arSessionManager = null;
  }

  Future<void> initialize({
    ARSessionManager? arSessionManager,
    ARObjectManager? arObjectManager,
    ARLocationManager? arLocationManager,
  }) async {
    this.arSessionManager = arSessionManager;
    this.arObjectManager = arObjectManager;
    this.arLocationManager = arLocationManager;

    this.arSessionManager?.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      showWorldOrigin: true,
      handleTaps: false,
    );
    this.arObjectManager?.onInitialize();

    if (arLocationManager != null) {
      final position = await arLocationManager.getLastKnownPosition();
      if (position != null) {
        transformationService = TransformationService(
          origin: Location(lat: position.latitude, lng: position.longitude),
        );
      }
      unawaited(loadPictures(position));
    }
  }

  Future<void> reload() async {
    final position = await arLocationManager?.getLastKnownPosition();
    return await loadPictures(position);
  }

  Future<void> loadPictures(Position? position) async {
    final net = networkService;
    if (position == null || net == null) {
      await clearPictures();
      return;
    }

    final results = await net.findNear(
      location: Location(lat: position.latitude, lng: position.longitude),
      radius: position.accuracy + 1000,
    );

    await clearPictures();
    for (final entry in results.entries) {
      for (final item in entry.value) {
        addPicture(item, provider: entry.key);
        return;
      }
    }
  }

  Future<void> clearPictures() async {
    for (final node in _nodes.values) {
      arObjectManager?.removeNode(node);
    }
    await databaseService?.deleteFiles('nodes/');
  }

  Future<void> addPicture(Picture picture, {String? provider}) async {
    final db = databaseService;
    final manager = arObjectManager;
    if (db == null || manager == null) {
      return;
    }

    final id = '$provider/${picture.id}';
    final nodeData = """{
  "scene": 0,
  "scenes" : [ {
    "nodes" : [ 0 ]
  } ],
  "nodes" : [ {
    "mesh" : 0
  } ],
  "meshes" : [ {
    "primitives" : [ {
      "attributes" : {
        "POSITION" : 1,
        "TEXCOORD_0" : 2
      },
      "indices" : 0,
      "material" : 0
    } ]
  } ],

  "materials" : [ {
    "pbrMetallicRoughness" : {
      "baseColorTexture" : {
        "index" : 0
      },
      "metallicFactor" : 0.0,
      "roughnessFactor" : 1.0
    }
  } ],

  "textures" : [ {
    "sampler" : 0,
    "source" : 0
  } ],
  "images" : [ {
    "uri" : "https://pastvu.com/_p/m/l/e/m/lemse4l0ha1gulzxv7.jpg"
  } ],
  "samplers" : [ {
    "magFilter" : 9729,
    "minFilter" : 9987,
    "wrapS" : 33648,
    "wrapT" : 33648
  } ],

  "buffers" : [ {
    "uri" : "data:application/gltf-buffer;base64,AAABAAIAAQADAAIAAAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAACAPwAAgD8AAAAAAAAAAAAAgD8AAAAAAACAPwAAgD8AAAAAAAAAAAAAAAAAAAAAAACAPwAAAAAAAAAA",
    "byteLength" : 108
  } ],
  "bufferViews" : [ {
    "buffer" : 0,
    "byteOffset" : 0,
    "byteLength" : 12,
    "target" : 34963
  }, {
    "buffer" : 0,
    "byteOffset" : 12,
    "byteLength" : 96,
    "byteStride" : 12,
    "target" : 34962
  } ],
  "accessors" : [ {
    "bufferView" : 0,
    "byteOffset" : 0,
    "componentType" : 5123,
    "count" : 6,
    "type" : "SCALAR",
    "max" : [ 3 ],
    "min" : [ 0 ]
  }, {
    "bufferView" : 1,
    "byteOffset" : 0,
    "componentType" : 5126,
    "count" : 4,
    "type" : "VEC3",
    "max" : [ 1.0, 1.0, 0.0 ],
    "min" : [ 0.0, 0.0, 0.0 ]
  }, {
    "bufferView" : 1,
    "byteOffset" : 48,
    "componentType" : 5126,
    "count" : 4,
    "type" : "VEC2",
    "max" : [ 1.0, 1.0 ],
    "min" : [ 0.0, 0.0 ]
  } ],

  "asset" : {
    "version" : "2.0"
  }
}
""";

    final path = await db.writeFile('model.gltf', nodeData);
    final text = await db.readText(path);
    debugPrint("[AR]: $text");

    final newNode = ARNode(
      type: NodeType.fileSystemAppFolderGLTF2,
      uri: path,
      scale: Vector3(0.2, 0.2, 0.2),
      position: Vector3(0.0, 0.0, 0.0),
      rotation: Vector4(1.0, 0.0, 0.0, 0.0),
      // scale: Vector3(0.2, 0.2, 0.2),
      // position: Vector3(0.0, 0.0, 0.0),
      // position: transformationService?.transformPosition(picture.location),
      // eulerAngles: transformationService?.transformOrientation(picture.bearing),
      // scale: transformationService?.transformScale(picture.location),
    );
    if (await manager.addNode(newNode) == true) {
      _nodes[id] = newNode;
      _pictures[id] = picture;
    } else {
      await db.deleteFiles('model.gltf');
    }
  }
}