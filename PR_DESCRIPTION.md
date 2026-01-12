## Change Summary
**What does this PR change?**
Refactors Aqua test suite into a modular structure with shared base class and adds comprehensive tests covering all require checks in ship/dock/push/pull/safeBalances functions.

**Related Issue/Ticket:**
- https://1inch.atlassian.net/browse/PT1-256
- https://1inch.atlassian.net/browse/PT1-259

## Changes

### Test Structure Refactoring
- Created `test/base/AquaTestBase.sol` - shared test setup (aqua, tokens, approvals)
- Created `test/mock/ERC20.sol` - extracted `MockToken` for reuse
- Split monolithic `Aqua.t.sol` into focused test files:
  - `AquaShipDock.t.sol` - Ship + Dock tests (9 tests)
  - `AquaPushPull.t.sol` - Push + Pull tests (8 tests)
  - `AquaBalances.t.sol` - Balance view function tests (10 tests)
  - `AquaLifecycle.t.sol` - Complex end-to-end scenarios (2 tests)
  - `AquaStorageTest.t.sol` - Storage/gas optimization tests (8 tests, unchanged)

### New Tests Added
| Function | Test | Require Check Covered |
|----------|------|----------------------|
| `ship` | `testShipRevertsWhenTokenCountEquals255` | `MaxNumberOfTokensExceeded` |
| `ship` | `testShipDockShipSameStrategyReverts` | `StrategiesMustBeImmutable` after dock |
| `dock` | `testDockNonExistentStrategyReverts` | `DockingShouldCloseAllTokens` |
| `dock` | `testDockAlreadyDockedStrategyReverts` | `DockingShouldCloseAllTokens` |
| `push` | `testPushSucceedsForActiveStrategy` | Happy path |
| `pull` | `testPullSucceedsForActiveStrategy` | Happy path |
| `pull` | `testPullRevertsOnInsufficientBalance` | Arithmetic underflow |
| `pull` | `testPullFromNonExistentStrategy` | Underflow on zero balance |
| `pull` | `testPullAfterDockRevertsOnUnderflow` | Underflow after dock |
| `safeBalances` | `testSafeBalancesRevertsIfFirstTokenNotInStrategy` | Line 32 require |
| `safeBalances` | `testSafeBalancesRevertsIfSecondTokenNotInStrategy` | Line 36 require |
| `safeBalances` | `testSafeBalancesRevertsIfBothTokensNotInStrategy` | Both tokens invalid |

### Test Count
- **Before:** 27 tests
- **After:** 37 tests (+10 new tests)

## Testing & Verification
**How was this tested?**
- [x] Unit tests
- [ ] Integration tests
- [ ] Manual testing (describe steps)
- [ ] Verified on staging

```
forge test --offline
Ran 5 test suites: 37 tests passed, 0 failed, 0 skipped
```

## Risk Assessment
**Risk Level:**
- [x] **Low** - Minor changes, no operational impact
- [ ] **Medium** - Moderate changes, limited impact, standard rollback available
- [ ] **High** - Significant changes, potential operational impact, complex rollback

**Risks & Impact**
- Test-only changes, no contract modifications
- No deployment or migration required
- No breaking changes to existing functionality
