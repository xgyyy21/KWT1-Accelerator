# Exploratory target only: 150 MHz. Not signoff constraints.
create_clock -name core_clk -period 6.666667 [get_ports clk]
# TODO platform: input/output delay, uncertainty, drive/load, reset release,
# SRAM macro clock/data timing with the target PVT Liberty files.
# No blanket false paths and no invented platform or memory timing values.
