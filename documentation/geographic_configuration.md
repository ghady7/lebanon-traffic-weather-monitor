# Geographic configuration

## Phase 3 — Lebanon locations and route configuration

This phase defines the core Lebanon geography used by the ETL pipeline. The design is intentionally configuration-driven so new routes can be added without rewriting Python logic.

## 1. Weather locations

The project includes representative weather observation points across the main Lebanese regions.

### Weather locations
- Beirut
- Dbayeh
- Jounieh
- Byblos
- Baabda
- Aley
- Tripoli
- Zahle
- Baalbek
- Saida
- Tyre

### Why these locations
These locations represent the major urban and intercity corridors relevant to traffic monitoring in Lebanon. They cover the city-center, coastal, inland, northern, eastern, and southern route patterns without trying to model every road or settlement.

## 2. Route configuration

The MVP contains 10 configured routes. This keeps the scope realistic without overspecifying the platform.

### Routes included
- Beirut → Dbayeh
- Beirut → Jounieh
- Beirut → Byblos
- Beirut → Baabda
- Beirut → Aley
- Beirut → Tripoli
- Beirut → Zahle
- Beirut → Saida
- Saida → Tyre
- Zahle → Baalbek

### Route-to-weather design
Each route references a single weather observation point that is geographically relevant to the corridor. This reduces duplicate weather requests and keeps API usage efficient.

Examples:
- Beirut → Jounieh uses Jounieh weather
- Beirut → Tripoli uses Tripoli weather
- Beirut → Zahle uses Zahle weather
- Saida → Tyre uses Tyre weather

## 3. Configuration-driven design

The route and weather definitions are centralized in the Python config package rather than spread across custom extraction functions. This means that adding a route requires updating the configuration rather than rewriting the ETL engine.

## 4. Validation requirements

The route configuration must satisfy the following before ETL execution:
- unique route IDs
- unique weather location IDs
- valid latitude/longitude bounds
- non-empty origin and destination names
- route-to-weather mapping must exist
- coordinates cannot be empty or malformed

## 5. Expected outputs

The configuration should produce a clean, consistent geography layer that can be used by:
- the extraction pipeline
- raw ingestion into dbo.staging_table
- future SQL dimensional loading
- Power BI geographic analysis

## 6. Common failure points

- duplicate route IDs
- duplicate weather location IDs
- invalid coordinates
- incomplete route metadata
- inconsistent route-to-weather mapping
- mismatched origin/destination names and coordinates

## 7. Next stage

After the geographic layer is validated, the next phase will build the SQL Server foundation and the raw staging table around the configured route and weather model.
