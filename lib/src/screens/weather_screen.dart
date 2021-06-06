import 'package:flutter/material.dart';
import 'package:flutter_weather/main.dart';
import 'package:flutter_weather/src/bloc/weather_event.dart';
import 'package:flutter_weather/src/bloc/weather_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_weather/src/widgets/weather_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';
import 'dart:convert';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_weather/src/api/http_exception.dart';
import '../bloc/weather_bloc.dart';
import 'dart:async';
import 'package:dio/dio.dart';
enum OptionsMenu { changeCity, settings }
String name;
class WeatherScreen extends StatefulWidget {
  @override
  _WeatherScreenState createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with TickerProviderStateMixin {
  WeatherBloc _weatherBloc;
  String _cityName = 'bengaluru';
  Animation<double> _fadeAnimation;
  AnimationController _fadeController;

  @override
  void initState() {
    super.initState();

    _weatherBloc = BlocProvider.of<WeatherBloc>(context);

    _fetchWeatherWithLocation().catchError((error) {
      _fetchWeatherWithCity();
    });

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    ThemeData appTheme = AppStateContainer.of(context).theme;

    return Scaffold(
        appBar: AppBar(
          backgroundColor: appTheme.primaryColor,
          elevation: 0,
          title: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                style: TextStyle(
                  color: appTheme.accentColor.withAlpha(80),
                  fontSize: 14,
                ),
              )
            ],
          ),
          actions: <Widget>[
            PopupMenuButton<OptionsMenu>(
                child: Icon(
                  Icons.more_vert,
                  color: appTheme.accentColor,
                ),
                onSelected: this._onOptionMenuItemSelected,
                itemBuilder: (context) => <PopupMenuEntry<OptionsMenu>>[
                  PopupMenuItem<OptionsMenu>(
                    value: OptionsMenu.changeCity,
                    child: Text("change city"),
                  ),
                  PopupMenuItem<OptionsMenu>(
                    value: OptionsMenu.settings,
                    child: Text("settings"),
                  ),
                ])
          ],
        ),
        backgroundColor: Colors.white,
        body: Material(
          child: Container(
            constraints: BoxConstraints.expand(),
            decoration: BoxDecoration(color: appTheme.primaryColor),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: BlocBuilder<WeatherBloc, WeatherState>(
                  builder: (_, WeatherState weatherState) {
                    _fadeController.reset();
                    _fadeController.forward();

                    if (weatherState is WeatherLoaded) {
                      this._cityName = weatherState.weather.cityName;
                      return WeatherWidget(
                        weather: weatherState.weather,
                      );
                    } else if (weatherState is WeatherError ||
                        weatherState is WeatherEmpty) {
                      String errorText = 'There was an error fetching weather data';
                      if (weatherState is WeatherError) {
                        if (weatherState.errorCode == 404) {
                          errorText =
                          'We have trouble fetching weather for $_cityName';
                        }
                      }
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                          SizedBox(
                            height: 10,
                          ),
                          Text(
                            errorText,
                            style: TextStyle(
                              color: Colors.red,
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              primary: appTheme.accentColor,
                              elevation: 1,
                            ),
                            child: Text("Try Again"),
                            onPressed: _fetchWeatherWithCity,
                          )
                        ],
                      );
                    } else if (weatherState is WeatherLoading) {
                      return Center(
                        child: CircularProgressIndicator(
                          backgroundColor: appTheme.primaryColor,
                        ),
                      );
                    }
                    return Container(
                      child: Text('No city set'),
                    );
                  }),
            ),
          ),
        ));
  }
  void onDataChange(val, position) {
    setState(() {
      this._cityName = val;
    });
    this._fetchWeatherwithLocationCity(position);

  }



  void _showCityChangeDialog() {
    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          ThemeData appTheme = AppStateContainer.of(context).theme;

          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text('Change city', style: TextStyle(color: Colors.black)),
            actions: <Widget>[
              TextButton(
                child: Text('ok'),
                style: TextButton.styleFrom(
                  primary: appTheme.accentColor,
                  elevation: 1,
                ),
                onPressed: () {
                  _fetchWeatherWithCity();
                  Navigator.of(context).pop();
                },
              ),
            ],
            content: Container(
              width: double.maxFinite,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Expanded(
                        child: ListView(
                            shrinkWrap: true,
                            children: <Widget>[

                              Center(
                                child: AutocompleteBasicExample( callback: (val, position) => onDataChange(val,position)),
                              ),
                            ]
                        )
                    )
                  ]
              ),
            ),

          );
        });
  }

  _onOptionMenuItemSelected(OptionsMenu item) {
    switch (item) {
      case OptionsMenu.changeCity:
        this._showCityChangeDialog();
        break;
      case OptionsMenu.settings:
        Navigator.of(context).pushNamed("/settings");
        break;
    }
  }
  _fetchWeatherwithLocationCity(List<dynamic> position){
    _weatherBloc.add(FetchWeather(
      longitude: position[0],
      latitude: position[1],
    ));
  }
  _fetchWeatherWithCity() {
    this._cityName=name;
    _weatherBloc.add(FetchWeather(cityName: _cityName));
  }
  _fetchWeatherWithLocation() async {
    var permissionResult = await Permission.locationWhenInUse.status;

    switch (permissionResult) {
      case PermissionStatus.restricted:
      case PermissionStatus.permanentlyDenied:
        print('location permission denied');
        _showLocationDeniedDialog();
        break;

      case PermissionStatus.denied:
        await Permission.locationWhenInUse.request();
        _fetchWeatherWithLocation();
        break;

      case PermissionStatus.limited:
      case PermissionStatus.granted:
        print('getting location');
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 2));

        print(position.toString());

        _weatherBloc.add(FetchWeather(
          longitude: position.longitude,
          latitude: position.latitude,
        ));
        break;
    }
  }
  void _showLocationDeniedDialog() {
    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          ThemeData appTheme = AppStateContainer.of(context).theme;

          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text('Location is disabled 🙁',
                style: TextStyle(color: Colors.black)),
            actions: <Widget>[
              TextButton(
                child: Text('Enable!'),
                style: TextButton.styleFrom(
                  primary: appTheme.accentColor,
                  elevation: 1,
                ),
                onPressed: () {
                  openAppSettings();
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });
  }
}


class AutocompleteBasicExample extends StatelessWidget {

  AutocompleteBasicExample({ Key key,this.callback})
      : super(key: key);
  final callback;
  var myController = TextEditingController();
  final apiKey = 'GqfwrZUEfxbwbnQUhtBMFivEysYIxelQ';
  Uri _buildUri(String endpoint, String cityName) {
    try {
      var query = {
        'text':cityName.toString(),
        'key':"GqfwrZUEfxbwbnQUhtBMFivEysYIxelQ"
      };
      var uri = Uri(
        scheme: 'https',
        host: 'apis.wemap.asia',
        path: 'geocode-1/$endpoint',
        queryParameters: query,
      );
      print('fetching $uri');
      return uri;
    }catch(ex) {
      print(ex.toString());
    }

  }
  Future<List<dynamic>> getCityName(String cityName) async {
    final uri = _buildUri('autocomplete', cityName);
    final http.Client httpClient = http.Client();
    final res = await httpClient.get(uri);
    final weatherJson = json.decode(res.body);
    print('${weatherJson['features']}');
    return weatherJson['features'];
  }
  void test(dynamic any){
    print('test $any');

  }
  @override
  Widget build(BuildContext context){
    return TypeAheadField(
        textFieldConfiguration: TextFieldConfiguration(
        autofocus: true,
        style: DefaultTextStyle.of(context).style.copyWith(
        fontStyle: FontStyle.italic
    ),
    decoration: InputDecoration(
    border: OutlineInputBorder()
    )
    ),
    suggestionsCallback: (pattern) async {
    return await getCityName(pattern);
    },
    itemBuilder: (context, suggestion) {

      return ListTile(
      leading: Icon(Icons.location_on),
      title: Text('${suggestion['properties']['name']}'),
      subtitle: Text('${suggestion['properties']['label']}'),
      );
    },
    onSuggestionSelected: (suggestion) {
          callback(suggestion['properties']['label'],suggestion['geometry']['coordinates']);
      test(suggestion.toString());
          Navigator.of(context).pop();
    });
  }
}
