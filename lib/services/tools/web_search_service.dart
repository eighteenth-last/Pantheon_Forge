import 'dart:convert';
import 'package:dio/dio.dart';

/// Web 搜索服务
class WebSearchService {
  static final Dio _dio = Dio();

  /// 使用 Tavily API 进行搜索
  static Future<WebSearchResult> searchWithTavily({
    required String query,
    required String apiKey,
    int maxResults = 5,
  }) async {
    final response = await _dio.post(
      'https://api.tavily.com/search',
      data: {
        'query': query,
        'api_key': apiKey,
        'search_depth': 'basic',
        'include_answer': true,
        'max_results': maxResults,
      },
      options: Options(
        headers: {'Content-Type': 'application/json'},
        validateStatus: (status) => status! < 500,
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Tavily search failed: ${response.statusMessage}');
    }

    final data = response.data as Map<String, dynamic>;
    final results = (data['results'] as List? ?? [])
        .map((e) => WebSearchItem(
          title: e['title'] as String? ?? '',
          url: e['url'] as String? ?? '',
          content: e['content'] as String? ?? '',
          score: (e['score'] as num?)?.toDouble(),
        ))
        .toList();

    return WebSearchResult(
      query: query,
      results: results,
      answer: data['answer'] as String?,
    );
  }

  /// 使用 SearXNG 进行搜索
  static Future<WebSearchResult> searchWithSearxng({
    required String query,
    required String baseUrl,
    int maxResults = 5,
  }) async {
    final response = await _dio.get(
      '$baseUrl/search',
      queryParameters: {
        'q': query,
        'format': 'json',
        'engines': 'google,bing,duckduckgo',
      },
      options: Options(
        validateStatus: (status) => status! < 500,
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('SearXNG search failed: ${response.statusMessage}');
    }

    final data = response.data as Map<String, dynamic>;
    final results = (data['results'] as List? ?? [])
        .take(maxResults)
        .map((e) => WebSearchItem(
          title: e['title'] as String? ?? '',
          url: e['url'] as String? ?? '',
          content: e['content'] as String? ?? '',
        ))
        .toList();

    return WebSearchResult(
      query: query,
      results: results,
    );
  }

  /// 通用搜索方法
  static Future<WebSearchResult> search({
    required String query,
    String provider = 'tavily',
    String? apiKey,
    String? baseUrl,
    int maxResults = 5,
  }) async {
    switch (provider) {
      case 'tavily':
        if (apiKey == null || apiKey.isEmpty) {
          throw Exception('Tavily API key is required');
        }
        return searchWithTavily(
          query: query,
          apiKey: apiKey,
          maxResults: maxResults,
        );
      case 'searxng':
        if (baseUrl == null || baseUrl.isEmpty) {
          throw Exception('SearXNG base URL is required');
        }
        return searchWithSearxng(
          query: query,
          baseUrl: baseUrl,
          maxResults: maxResults,
        );
      default:
        throw Exception('Unsupported search provider: $provider');
    }
  }
}

/// 搜索结果
class WebSearchResult {
  final String query;
  final List<WebSearchItem> results;
  final String? answer;

  WebSearchResult({
    required this.query,
    required this.results,
    this.answer,
  });

  /// 格式化为文本供 LLM 使用
  String toFormattedText() {
    final buffer = StringBuffer();
    buffer.writeln('Web search results for: "$query"');
    buffer.writeln();

    if (answer != null && answer!.isNotEmpty) {
      buffer.writeln('Quick Answer:');
      buffer.writeln(answer);
      buffer.writeln();
    }

    buffer.writeln('Search Results:');
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      buffer.writeln('${i + 1}. ${result.title}');
      buffer.writeln('   URL: ${result.url}');
      buffer.writeln('   ${result.content}');
      buffer.writeln();
    }

    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'query': query,
    'answer': answer,
    'results': results.map((e) => e.toJson()).toList(),
  };
}

/// 搜索条目
class WebSearchItem {
  final String title;
  final String url;
  final String content;
  final double? score;

  WebSearchItem({
    required this.title,
    required this.url,
    required this.content,
    this.score,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'content': content,
    'score': score,
  };
}
