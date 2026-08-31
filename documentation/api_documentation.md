# API documentation

## Phase 2 — API accounts and API testing

This phase validates the external contracts before the ETL pipeline is built. The goal is to confirm the data shape, key fields, timestamp semantics, and failure modes for each API that feeds the warehouse.

## 1. TomTom Routing API

### Purpose
The TomTom Routing API provides route-level traffic-aware travel information for each configured corridor. It is the source for route travel time, no-traffic travel time, delay, and route distance.

### Endpoint pattern
The route request pattern for a road trip is conceptually:

`https://api.tomtom.com/routing/1/calculateRoute/{origin_lat},{origin_lon}:{destination_lat},{destination_lon}/json?key={API_KEY}&travelMode=car&traffic=true&computeTravelTimeFor=all`

### Example
For Beirut to Jounieh, the request is based on the origin and destination coordinates in the route configuration.

### Fields to capture from the response
- routeSummary
  - lengthInMeters
  - travelTimeInSeconds
  - trafficDelayInSeconds
  - noTrafficTravelTimeInSeconds
- legs
  - departureTime
  - arrivalTime
  - summary
- routeSections
  - travelMode
  - traffic
  - summary

### Why these fields matter
- `travelTimeInSeconds` gives the observed travel time during the current traffic conditions.
- `noTrafficTravelTimeInSeconds` gives the baseline travel time under free-flow conditions.
- `trafficDelayInSeconds` is used to quantify congestion and delay.
- `lengthInMeters` is converted to distance used in the fact table.

### Validation rules
- Route ID cannot be null.
- Origin and destination coordinates must be valid.
- Response must contain route summary data.
- Travel time, no-traffic travel time, and delay should be numeric and not negative.
- Any failed response must be logged and never silently converted into fabricated measurements.

### Known limitations
- Traffic data is an API estimate, not a physical roadside sensor reading.
- Route and traffic conditions can vary by time of day, roadworks, and provider availability.
- API quotas and rate limits must be respected.
- TomTom may return partial or error responses under service issues.

## 2. OpenWeather API

### Purpose
OpenWeather provides weather observations for each configured geographic point. Each route is associated with the weather observation point nearest to its route context, such as Jounieh or Zahle.

### Endpoint pattern
The general current-weather request pattern is:

`https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={API_KEY}&units=metric`

### Example
Use the weather point tied to Jounieh when collecting data for the Beirut → Jounieh route.

### Fields to capture from the response
- `coord`
  - `lon`
  - `lat`
- `main`
  - `temp`
  - `feels_like`
  - `humidity`
  - `pressure`
- `visibility`
- `wind`
  - `speed`
  - `deg`
- `clouds`
  - `all`
- `rain`
  - `1h`
- `snow`
  - `1h`
- `weather[]`
  - `id`
  - `main`
  - `description`
- `dt`

### Why these fields matter
- They provide the weather conditions associated with a route observation.
- They are later mapped into `dim_weather` and used in Power BI for weather-vs-traffic analysis.
- They help separate observed traffic conditions from future prediction inputs.

### Validation rules
- Temperature must be numeric.
- Humidity must be within realistic bounds.
- Rain and snow values cannot be negative.
- Wind speed cannot be negative.
- Visibility cannot be negative.
- Weather timestamps must be preserved and interpreted in the correct timezone.

### Known limitations
- OpenWeather points represent a single observation site, not a complete route weather model.
- Some fields may be absent in the response depending on the weather conditions and API plan.
- The weather source should be treated as observational data, not a causal source of traffic behavior.

## 3. Timezone strategy

The project must treat all reporting in Asia/Beirut time. The pipeline must explicitly distinguish between:
- source/API timestamps
- UTC timestamps where applicable
- ingestion timestamps
- local reporting timestamps in Asia/Beirut

This is required to ensure route and weather observations are not silently shifted when stored or reported.

## 4. Data-quality objectives for this phase

Before the ETL pipeline is built, the API testing process must confirm that:
- credentials are valid
- JSON payloads match expected shapes
- required route and weather fields are present
- time fields are understood correctly
- error responses are handled explicitly
- partial failures do not silently create invalid records

## 5. Expected results from this phase

When the .env file contains valid keys, the API test script should successfully fetch data from both providers and log the response metadata. If the keys are absent or still placeholder values, the script should skip live calls and explain the reason instead of failing unpredictably.

## 6. Common failure points

- Missing or invalid API keys
- Rate limiting or blocked requests
- Invalid geographic coordinates
- Unexpected JSON schema changes
- Timeouts or partial responses
- API-side service outages
- Confusion between UTC timestamps and local reporting time

## 7. API contract discipline

The ETL design must maintain a strict separation between:
- raw source payloads
- validated route data
- validated weather data
- derived warehouse facts

This separation preserves traceability and supports future auditing and troubleshooting.
