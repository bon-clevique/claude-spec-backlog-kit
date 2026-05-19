# Coding Standards

## Core Principles
- **Immutability**: Return new objects. Never mutate existing ones
- **File size**: 200–400 lines standard, 800 max. Split by feature/domain
- **Functions**: ≤50 lines, ≤4 nesting levels
- **Error handling**: Handle explicitly at every level. Never swallow errors
- **Input validation**: Validate at system boundaries (user input, external APIs)
- Language-specific details → project `.claude/rules/<lang>/`

## Code Quality Checklist
- [ ] Readable, well-named code | Functions <50 lines | Files <800 lines
- [ ] No deep nesting (>4 levels) | Proper error handling
- [ ] No hardcoded values | Immutable patterns used

## Design Patterns
- **Repository**: findAll/findById/create/update/delete interface. Business logic depends on abstract interface
- **API Response**: Consistent envelope (success, data, error, pagination)

## Security Checks (Before ANY commit)
- [ ] No hardcoded secrets | User inputs validated | Parameterized queries
- [ ] XSS/CSRF prevention | Auth verified | Rate limiting | No sensitive data in errors
- If issue found → **security-reviewer** agent → fix → review entire codebase

## Testing Strategy (AI-Optimized)

### Inverted Test Pyramid
In AI-assisted development, investing in integration and E2E layers yields higher returns than blanket unit test coverage.

| Priority | Layer | What to Test | When |
|----------|-------|-------------|------|
| **1 (max investment)** | E2E / on-device | Critical paths (billing, auth, data sync) | After feature is complete |
| **2** | Integration | API boundaries, DB operations, external service integration | When implementing API/DB layer |
| **3 (minimal)** | Unit | Complex business logic, state transitions, calculations, validation | Complex logic only |

### When to Apply TDD
Apply TDD (RED→GREEN→IMPROVE) only in these cases:
- Complex state transitions (FSM, workflows)
- Logic requiring strict correctness (monetary calculations, date arithmetic)
- Reproducing existing bugs → fix (as regression tests)

### Quality
- Independent, deterministic, behavior-focused
- **Deciding what to test** matters more than the volume of test code
- Define the test strategy in the plan's Acceptance Criteria before implementing

### Anti-patterns
- Tests written solely to inflate coverage numbers
- AI mass-generating trivial tests (ones that obviously pass)
- Unit-testing items that can only be verified on a real device
- Excessive mocking (risk of diverging from real behavior)
