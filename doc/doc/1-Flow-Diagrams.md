# Flow Diagrams

## 1. Application Workflow (User's Perspective)

This diagram shows the complete user journey through the app, from entering job URLs to exporting the final PDF.

```mermaid
flowchart TD
    A([App Start]) --> B[Screen 1: Stelleneingabe]
    B --> C{URLs entered?}
    C -->|No| D[Show hint text]
    D --> B
    C -->|Yes| E[Validate URLs]
    E --> F{Valid URLs?}
    F -->|No| G[Show error: invalid URLs]
    G --> B
    F -->|Yes| H[Store URLs in Repository]
    H --> I[Navigate to Screen 3]

    B --> J[Optional: Job Search]
    J --> K[Screen 2: Jobsuche]
    K --> L{Search criteria entered?}
    L -->|No| M[Prompt for job description]
    M --> K
    L -->|Yes| N[Perform API search]
    N --> O{Results found?}
    O -->|No| P[Show empty state]
    P --> K
    O -->|Yes| Q[Show results list]
    Q --> R{Adopt results?}
    R -->|No| K
    R -->|Yes| S[Add selected jobs to Repository]
    S --> I

    I --> T[Screen 3: Ergebnisübersicht]
    T --> U[Create Application objects]
    U --> V[Display application list]
    V --> W{Per application:}
    W -->|Completed| X[Show green checkmark]
    W -->|Failed| Y[Show red error + retry button]
    W -->|Processing| Z[Show blue sync icon]
    W -->|Queued| AA[Show grey hourglass]
    W -->|Exported| AB[Show teal cloud icon]

    X --> AC[Tap to view detail]
    Y --> AD[Press retry button]
    AD --> AE[Reset to queued]
    AE --> V
    X --> AF[Press export all]
    AF --> AG[Mark all completed as exported]
    AG --> AH[Show success snackbar]

    AC --> AI[Screen 3a: Detailansicht]
    AI --> AJ{Actions:}
    AJ --> AK[Download PDF]
    AJ --> AL[Regenerate]
    AJ --> AM[Delete]
    AL --> AN[Reset status to queued]
    AN --> V
    AM --> AO[Remove from list]
    AO --> V
    AK --> AP[Trigger file save]
    AP --> V
```

## 2. State Flow (Application Lifecycle)

Each application goes through a defined lifecycle:

```mermaid
stateDiagram-v2
    [*] --> Queued: URL validated
    Queued --> Processing: Generation starts
    Processing --> Completed: PDF generated
    Processing --> Failed: Error occurred
    Failed --> Queued: User retries
    Completed --> Exported: User exports
    Completed --> Queued: User regenerates
    Exported --> Queued: User regenerates
    Queued --> [*]: User deletes
    Processing --> [*]: User deletes
    Completed --> [*]: User deletes
    Failed --> [*]: User deletes
    Exported --> [*]: User deletes
```

### Status Descriptions

| Status | Icon | Color | Meaning |
|--------|------|-------|---------|
| **Queued** | `hourglass_empty` | Grey | Awaiting processing |
| **Processing** | `sync` | Blue | Generation in progress |
| **Completed** | `check_circle` | Green | PDF ready |
| **Failed** | `error` | Red | Error occurred, retry available |
| **Exported** | `cloud_done` | Teal | PDF has been exported |

## 3. Navigation Flow (go_router)

```mermaid
flowchart LR
    A["`/`<br/>Stelleneingabe`"] -->|"Weiter"| C["`/applications`<br/>Ergebnisübersicht`"]
    A -->|"Jobsuche"| B["`/search`<br/>Jobsuche`"]
    B -->|"Übernehmen"| C
    C -->|"Zurück"| A
    C -->|"Zurück"| B
    C -->|"Tippen"| D["`/applications/:id`<br/>Detailansicht`"]
    D -->|"Zurück"| C

    style A fill:#bbdefb
    style B fill:#c8e6c9
    style C fill:#fff9c4
    style D fill:#f8bbd0
```

### Redirect Guard Logic

```mermaid
flowchart TD
    A[User navigates] --> B{Is route `/applications`<br/>or `/applications/:id`?}
    B -->|No| C[Allow navigation]
    B -->|Yes| D{Has valid URLs or<br/>applications in repository?}
    D -->|Yes| C
    D -->|No| E[Redirect to `/`]
```

## 4. Data Flow (Screen to Screen)

```mermaid
sequenceDiagram
    participant S1 as Screen 1: Stelleneingabe
    participant S2 as Screen 2: Jobsuche
    participant Repo as JobRepository
    participant S3 as Screen 3: Ergebnisübersicht
    participant S3a as Screen 3a: Detailansicht

    Note over S1,S3a: All data flows through JobRepository

    S1->>S1: User enters URLs
    S1->>S1: Validate URLs
    S1->>Repo: addValidatedUrls(urls)
    S1->>S3: Navigate to /applications

    S2->>S2: User enters search criteria
    S2->>S2: Perform API search (mock)
    S2->>Repo: addJobsFromSearch(jobIds)
    S2->>S3: Navigate to /applications

    S3->>Repo: createApplicationsFromUrls()
    S3->>S3: Display application list
    S3->>Repo: updateApplicationStatus(id, status)
    S3->>S3a: Navigate to /applications/:id

    S3a->>Repo: getApplication(id)
    S3a->>S3a: Display detail view
    S3a->>Repo: updateApplicationStatus(id, queued)
    S3a->>Repo: removeApplication(id)
    S3a->>S3: Navigate back
```

## 5. Logging Flow

```mermaid
flowchart LR
    A[App Event] --> B[Module-Specific Logger]
    B --> C{Log Level?}

    C -->|ERROR| D[Logger.severe()]
    D --> E[Console output]
    D --> F[File output (production)]

    C -->|WARNING| G[Logger.warning()]
    G --> E
    G --> F

    C -->|INFO| H[Logger.info()]
    H --> E
    H --> F

    C -->|DEBUG| I[Logger.fine()]
    I --> E
    I --> F

    F --> J[app_log.txt]
    J --> K{Rotation needed?}
    K -->|> 5 MB| L[Rotate to .0, .1, .2]
    K -->|<= 5 MB| M[Keep writing]

    style D fill:#ffcdd2
    style G fill:#fff9c4
    style H fill:#c8e6c9
    style I fill:#e0e0e0
```

### Log Level Configuration by Environment

| Environment | Log Level | Output |
|-------------|-----------|--------|
| **Development** | `Level.ALL` (DEBUG) | Console only |
| **Test / UAT** | `Level.INFO` | Console + File |
| **Production** | `Level.WARNING` | File only |

## 6. Complete System Interaction

```mermaid
flowchart TD
    subgraph "User Interface"
        A["`Stelleneingabe<br/>Screen 1`"]
        B["`Jobsuche<br/>Screen 2`"]
        C["`Ergebnisübersicht<br/>Screen 3`"]
        D["`Detailansicht<br/>Screen 3a`"]
    end

    subgraph "Data Layer"
        E["`JobRepository<br/>(Riverpod Provider)`"]
    end

    subgraph "Core Services"
        F["`AppLogger<br/>(Logging)`"]
        G["`AppThemeProvider<br/>(Theme)`"]
    end

    subgraph "External"
        H["`Job APIs<br/>(future)`"]
        I["`File System<br/>(PDF storage)`"]
    end

    A -->|validate + store URLs| E
    B -->|store search results| E
    E -->|read applications| C
    E -->|read single app| D
    C -->|status updates| E
    D -->|update / delete| E

    A -->|"Option: Search"| B

    F -.->|logging| A
    F -.->|logging| B
    F -.->|logging| C
    F -.->|logging| D
    F -.->|logging| E

    G -.->|theme| A
    G -.->|theme| B
    G -.->|theme| C
    G -.->|theme| D

    H -..->|search results| B
    C -.->|export PDFs| I