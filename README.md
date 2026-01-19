# EA Gold Scalper (XAUUSD)

EA modular para scalping en Gold (XAUUSD) durante NY session, usando FVG/BOS/OB. Riesgo fijo 0.3% por trade.

## Estructura
- Gold_Scalper.mq5: Main EA.
- Agents/: Agentes para análisis.
- Core/: Managers para riesgo, ejecución, etc.
- Monitoring/: Health y logging.
- Tests/: Suite de tests.

## Cómo Correr Tests
1. Abre MT5.
2. Compila Tests/TestSuite.mq5.
3. Ejecuta como script: Verifica "Todos PASSED".
