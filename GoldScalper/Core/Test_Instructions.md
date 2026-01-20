# QA Test Instructions (for Draft PR)

Follow the QA checklist in the PR description. Quick steps:

1. Compile:
   - Open MetaEditor, load `GoldScalper/Core/ExecutionEngine.mqh` and `Gold_Scalper.mq5` and compile the EA.
   - Attach to chart on demo.

2. TestPartialFill:
   - Run Tests/SimulatePartialFill.mq5 (script) while EA running.
   - Inspect `pending_requests.csv` and `expected_map.csv` in Common Files folder.

3. Kill-switch:
   - In script or console run: g_state_manager.SetKillSwitch(true);
   - Attempt to trigger Execute (via orchestrator or manual call). ExecutionEngine.Execute should reject.

4. Spread/tick:
   - Verify SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE) is used; compare against broker quotes.

Collect logs (TraceAlert) and CSVs, paste into TEST_RESULTS.md.
