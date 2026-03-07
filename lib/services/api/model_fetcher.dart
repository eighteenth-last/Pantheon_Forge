import 'package:dio/dio.dart';
import 'package:pantheon_forge/models/models.dart';

class ModelFetchResult {
  final List<AIModelConfig> models;
  final String? error;

  ModelFetchResult({required this.models, this.error});
}

class ModelFetcherService {
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Fetch models from OpenAI-compatible /v1/models endpoint
  static Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
    required ProviderType providerType,
  }) async {
    try {
      final url = baseUrl.endsWith('/') ? '${baseUrl}models' : '$baseUrl/models';
      
      // Configure headers - all providers use Bearer token
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };
      
      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode == 404) {
        return ModelFetchResult(
          models: [],
          error: '接口不存在 (404)\n该供应商可能不支持模型列表接口\n请手动添加模型',
        );
      }
      
      if (response.statusCode != 200) {
        return ModelFetchResult(
          models: [],
          error: 'HTTP ${response.statusCode}: ${response.statusMessage ?? "Unknown error"}',
        );
      }

      final data = response.data as Map<String, dynamic>;
      final modelsData = data['data'] as List? ?? [];

      // Filter and sort models
      final allModels = modelsData
          .map((m) => _parseModel(m as Map<String, dynamic>, providerType))
          .where((m) => m != null)
          .cast<AIModelConfig>()
          .toList();

      // Filter: only chat models, exclude image/video/embedding/audio/tts models
      final chatModels = allModels.where((m) {
        final id = m.id.toLowerCase();
        // Exclude non-chat models
        if (id.contains('embedding') || 
            id.contains('whisper') ||
            id.contains('tts') ||
            id.contains('dall-e') ||
            id.contains('imagen') ||
            id.contains('stable-diffusion') ||
            id.contains('midjourney') ||
            id.contains('text-to-video') ||
            id.contains('video') && !id.contains('video-understanding')) {
          return false;
        }
        return true;
      }).toList();

      // Sort: newer models first (heuristic based on version numbers in name)
      chatModels.sort((a, b) {
        // Prioritize models with higher version numbers (e.g., gpt-4o > gpt-4, claude-3.5 > claude-3)
        final aVer = _extractVersion(a.id);
        final bVer = _extractVersion(b.id);
        if (aVer != bVer) return bVer.compareTo(aVer);
        
        // Fallback: alphabetical
        return a.id.compareTo(b.id);
      });

      // Limit to top 20 models to avoid overwhelming UI
      final topModels = chatModels.take(20).toList();

      return ModelFetchResult(models: topModels);
    } on DioException catch (e) {
      String errorMsg = 'Network error';
      if (e.response != null) {
        final statusCode = e.response!.statusCode;
        if (statusCode == 401) {
          errorMsg = 'API Key 验证失败 (401)\n请检查 API Key 是否正确';
        } else if (statusCode == 403) {
          errorMsg = '权限不足 (403)\n请检查 API Key 权限';
        } else if (statusCode == 404) {
          errorMsg = '接口不存在 (404)\n该供应商可能不支持模型列表接口\n请手动添加模型';
        } else if (statusCode == 429) {
          errorMsg = '请求限制 (429)\n请稍后再试';
        } else if (statusCode != null && statusCode >= 500) {
          errorMsg = '服务器错误 ($statusCode)\n请稍后再试';
        } else {
          errorMsg = 'HTTP 错误 ($statusCode): ${e.response!.statusMessage ?? "Unknown error"}';
        }
      } else {
        errorMsg = '网络错误: ${e.message ?? "请检查网络连接"}';
      }
      return ModelFetchResult(models: [], error: errorMsg);
    } catch (e) {
      return ModelFetchResult(
        models: [],
        error: '未知错误: ${e.toString()}',
      );
    }
  }

  static AIModelConfig? _parseModel(Map<String, dynamic> json, ProviderType type) {
    try {
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) return null;

      // Use 'id' field as both id and name, or 'name' if available
      final name = (json['name'] as String?) ?? id;
      
      return AIModelConfig(
        id: id,
        name: name,
        type: type,
        enabled: true,
        category: ModelCategory.chat,
        supportsVision: _supportsVision(id),
        supportsFunctionCall: true,
        supportsThinking: _supportsThinking(id),
      );
    } catch (_) {
      return null;
    }
  }

  static double _extractVersion(String modelId) {
    // Extract version numbers like "4o", "3.5", "2.1" from model IDs
    final regex = RegExp(r'(\d+(\.\d+)?)');
    final matches = regex.allMatches(modelId);
    if (matches.isEmpty) return 0.0;
    
    // Return the largest version number found
    return matches
        .map((m) => double.tryParse(m.group(0) ?? '0') ?? 0.0)
        .reduce((a, b) => a > b ? a : b);
  }

  static bool _supportsVision(String modelId) {
    final lower = modelId.toLowerCase();
    return lower.contains('vision') ||
        lower.contains('gpt-4o') ||
        lower.contains('gpt-4-turbo') ||
        lower.contains('claude-3') ||
        lower.contains('gemini') && lower.contains('pro');
  }

  static bool _supportsThinking(String modelId) {
    final lower = modelId.toLowerCase();
    return lower.contains('o1') ||
        lower.contains('o3') ||
        lower.contains('thinking') ||
        lower.contains('reasoning');
  }
}
