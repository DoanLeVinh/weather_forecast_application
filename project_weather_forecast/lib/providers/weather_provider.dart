import 'package:flutter/material.dart';
import '../models/weather_model.dart';
import '../models/forecast_model.dart';
import '../models/city_suggestion.dart';
import '../models/saved_city.dart';
import '../services/openweather_service.dart';
import '../services/speech_service.dart';
import '../services/saved_cities_service.dart';
import 'package:geolocator/geolocator.dart';

class WeatherProvider with ChangeNotifier {
  final OpenWeatherService _weatherService = OpenWeatherService();
  final SpeechService _speechService = SpeechService();
  final SavedCitiesService _savedCitiesService = SavedCitiesService();

  WeatherModel? _currentWeather;
  ForecastModel? _forecast;
  List<CitySuggestion> _citySuggestions = [];
  List<SavedCity> _savedCities = [];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _isListening = false;
  bool _isCurrentCitySaved = false;
  String? _error;
  String _searchQuery = '';

  WeatherModel? get currentWeather => _currentWeather;
  ForecastModel? get forecast => _forecast;
  List<CitySuggestion> get citySuggestions => _citySuggestions;
  List<SavedCity> get savedCities => _savedCities;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get isListening => _isListening;
  bool get isCurrentCitySaved => _isCurrentCitySaved;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  // Initialize with current location
  Future<void> initializeWithLocation() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint(
          'Location permission denied forever, using default location',
        );
        // Fallback to Ho Chi Minh City
        await fetchWeatherByCoords(10.8231, 106.6297);
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (permission == LocationPermission.denied) {
        debugPrint('Location permission denied, using default location');
        // Fallback to Ho Chi Minh City
        await fetchWeatherByCoords(10.8231, 106.6297);
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Get current position with timeout
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );

        debugPrint('Got location: ${position.latitude}, ${position.longitude}');

        // Fetch weather data
        await fetchWeatherByCoords(position.latitude, position.longitude);
      } catch (locationError) {
        debugPrint('Error getting location: $locationError, using default');
        // Timeout hoặc lỗi GPS, fallback to Ho Chi Minh City
        await fetchWeatherByCoords(10.8231, 106.6297);
      }
    } catch (e) {
      debugPrint('Error in initializeWithLocation: $e');
      _error = e.toString();
      // Fallback to Ho Chi Minh City
      await fetchWeatherByCoords(10.8231, 106.6297);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch weather by city name
  Future<void> fetchWeatherByCity(String cityName) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentWeather = await _weatherService.getCurrentWeatherByCity(cityName);
      _forecast = await _weatherService.getForecastByCity(cityName);
      await _checkIfCurrentCitySaved();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch weather by coordinates
  Future<void> fetchWeatherByCoords(double lat, double lon) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentWeather = await _weatherService.getCurrentWeatherByCoords(
        lat,
        lon,
      );
      _forecast = await _weatherService.getForecastByCoords(lat, lon);
      await _checkIfCurrentCitySaved();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Search city suggestions
  Future<void> searchCities(String query) async {
    _searchQuery = query;
    notifyListeners();

    if (query.isEmpty || query.length < 2) {
      _citySuggestions = [];
      notifyListeners();
      return;
    }

    try {
      _citySuggestions = await _weatherService.getCitySuggestions(query);
    } catch (e) {
      _citySuggestions = [];
    }
    notifyListeners();
  }

  // Select city from suggestions
  Future<void> selectCity(CitySuggestion city) async {
    _searchQuery = city.displayName;
    _citySuggestions = [];
    _isSearching = false;
    notifyListeners();

    await fetchWeatherByCoords(city.lat, city.lon);
  }

  // Voice search
  Future<void> startVoiceSearch() async {
    _isListening = true;
    notifyListeners();

    try {
      final result = await _speechService.listen();
      if (result != null && result.isNotEmpty) {
        _searchQuery = result;
        await searchCities(result);
      }
    } catch (e) {
      _error = 'Lỗi nhận dạng giọng nói: $e';
    } finally {
      _isListening = false;
      notifyListeners();
    }
  }

  // Stop voice search
  Future<void> stopVoiceSearch() async {
    await _speechService.stop();
    _isListening = false;
    notifyListeners();
  }

  // Toggle search mode
  void toggleSearch() {
    _isSearching = !_isSearching;
    if (!_isSearching) {
      _searchQuery = '';
      _citySuggestions = [];
    }
    notifyListeners();
  }

  // Clear search
  void clearSearch() {
    _searchQuery = '';
    _citySuggestions = [];
    notifyListeners();
  }

  // Get tile layer URL
  String getTileLayerUrl(String layerType) {
    return _weatherService.getTileLayerUrl(layerType);
  }

  // Load saved cities
  Future<void> loadSavedCities() async {
    _savedCities = await _savedCitiesService.getSavedCities();
    await _checkIfCurrentCitySaved();
    notifyListeners();
  }

  // Save current city
  Future<bool> saveCurrentCity() async {
    if (_currentWeather == null) return false;

    final city = SavedCity(
      name: _currentWeather!.cityName,
      displayName: _currentWeather!.cityName,
      country: '', // Could be added to WeatherModel if needed
      lat: _currentWeather!.lat,
      lon: _currentWeather!.lon,
      savedAt: DateTime.now(),
    );

    final success = await _savedCitiesService.saveCity(city);
    if (success) {
      await loadSavedCities();
    }
    return success;
  }

  // Remove saved city
  Future<bool> removeSavedCity(SavedCity city) async {
    final success = await _savedCitiesService.removeCity(city);
    if (success) {
      await loadSavedCities();
    }
    return success;
  }

  // Check if current city is saved
  Future<void> _checkIfCurrentCitySaved() async {
    if (_currentWeather == null) {
      _isCurrentCitySaved = false;
      return;
    }

    _isCurrentCitySaved = await _savedCitiesService.isCitySaved(
      _currentWeather!.lat,
      _currentWeather!.lon,
    );
  }

  // Toggle save current city
  Future<void> toggleSaveCurrentCity() async {
    if (_isCurrentCitySaved) {
      // Remove
      final city = _savedCities.firstWhere(
        (c) => c.lat == _currentWeather!.lat && c.lon == _currentWeather!.lon,
      );
      await removeSavedCity(city);
    } else {
      // Save
      await saveCurrentCity();
    }
  }
}
