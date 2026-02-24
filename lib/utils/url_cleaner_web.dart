import 'dart:html' as html;

void cleanUrlParameter(String key) {
  try {
    final currentUri = Uri.parse(html.window.location.href);
    final newQueryParams = Map<String, String>.from(currentUri.queryParameters);
    
    if (newQueryParams.containsKey(key)) {
        newQueryParams.remove(key);
        
        // Remove query parameters completely if none remain
        final newUri = currentUri.replace(queryParameters: newQueryParams.isEmpty ? {} : newQueryParams);
        
        String newUrl = newUri.toString();
        if (newUrl.endsWith('?')) {
            newUrl = newUrl.substring(0, newUrl.length - 1);
        }
        
        // Rewrite the URL bar without reloading the page
        html.window.history.replaceState(null, '', newUrl);
    }
  } catch (e) {
    print("Failed to clean url: \$e");
  }
}
