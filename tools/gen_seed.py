#!/usr/bin/env python3
"""Generates src/assets/seed.sql for the PC Parts Depot catalog.

Run from repo root:  python tools/gen_seed.py
The committed seed.sql is the source of truth; this script just regenerates it.
"""
import os

CATEGORIES = [
    ("CPU", "Processors", "Desktop CPUs from AMD and Intel"),
    ("GPU", "Graphics Cards", "Discrete gaming and workstation GPUs"),
    ("RAM", "Memory", "DDR4 and DDR5 memory kits"),
    ("SSD", "Storage", "NVMe SSDs, SATA SSDs and hard drives"),
    ("MBD", "Motherboards", "ATX, mATX and ITX motherboards"),
    ("PSU", "Power Supplies", "80 PLUS rated ATX power supplies"),
    ("CASE", "Cases", "Mid-tower, full-tower and ITX PC cases"),
    ("COOL", "Cooling", "Air and liquid CPU coolers"),
    ("MON", "Monitors", "Gaming and productivity monitors"),
    ("KBD", "Keyboards", "Mechanical and membrane keyboards"),
    ("MOU", "Mice", "Wired and wireless gaming mice"),
    ("PRE", "Prebuilt PCs", "Ready-to-go desktop systems"),
]

# (sku, name, brand, price, specs, stock, description)
PRODUCTS = {
    "CPU": [
        ("CPU-AMD-7800X3D", "AMD Ryzen 7 7800X3D", "AMD", 359.00, "8C/16T, 4.2/5.0GHz, AM5, 96MB L3, 120W", 24, "3D V-Cache gaming flagship for AM5."),
        ("CPU-AMD-7950X", "AMD Ryzen 9 7950X", "AMD", 549.00, "16C/32T, 4.5/5.7GHz, AM5, 80MB cache, 170W", 14, "Top-tier multithreaded Zen 4 processor."),
        ("CPU-AMD-7600X", "AMD Ryzen 5 7600X", "AMD", 229.00, "6C/12T, 4.7/5.3GHz, AM5, 38MB cache, 105W", 41, "Mainstream AM5 gaming CPU."),
        ("CPU-AMD-5700X3D", "AMD Ryzen 7 5700X3D", "AMD", 199.00, "8C/16T, 3.0/4.1GHz, AM4, 96MB L3, 105W", 33, "Budget 3D V-Cache upgrade for AM4."),
        ("CPU-INT-14900K", "Intel Core i9-14900K", "Intel", 569.00, "24C/32T, up to 6.0GHz, LGA1700, 36MB L3", 11, "Flagship Raptor Lake Refresh CPU."),
        ("CPU-INT-14700K", "Intel Core i7-14700K", "Intel", 399.00, "20C/28T, up to 5.6GHz, LGA1700, 33MB L3", 18, "High-performance desktop processor."),
        ("CPU-INT-14600K", "Intel Core i5-14600K", "Intel", 309.00, "14C/20T, up to 5.3GHz, LGA1700, 24MB L3", 27, "Excellent mid-range gaming CPU."),
        ("CPU-INT-13400F", "Intel Core i5-13400F", "Intel", 189.00, "10C/16T, up to 4.6GHz, LGA1700, no iGPU", 38, "Affordable 10-core for gaming builds."),
    ],
    "GPU": [
        ("GPU-NV-4090", "NVIDIA GeForce RTX 4090 24GB", "NVIDIA", 1799.00, "24GB GDDR6X, 16384 CUDA, 2520MHz boost", 6, "Halo-tier 4K and content creation GPU."),
        ("GPU-NV-4080S", "NVIDIA GeForce RTX 4080 SUPER 16GB", "NVIDIA", 999.00, "16GB GDDR6X, 10240 CUDA, 2550MHz boost", 9, "High-end 4K gaming card."),
        ("GPU-NV-4070S", "NVIDIA GeForce RTX 4070 SUPER 12GB", "NVIDIA", 599.00, "12GB GDDR6X, 7168 CUDA, 2475MHz boost", 16, "Strong 1440p performance."),
        ("GPU-NV-4060", "NVIDIA GeForce RTX 4060 8GB", "NVIDIA", 299.00, "8GB GDDR6, 3072 CUDA, 2460MHz boost", 30, "Efficient 1080p gaming GPU."),
        ("GPU-AMD-7900XTX", "AMD Radeon RX 7900 XTX 24GB", "AMD", 949.00, "24GB GDDR6, 6144 SP, RDNA 3, 2500MHz", 8, "High-VRAM 4K Radeon flagship."),
        ("GPU-AMD-7800XT", "AMD Radeon RX 7800 XT 16GB", "AMD", 499.00, "16GB GDDR6, 3840 SP, RDNA 3", 12, "Great value 1440p card."),
        ("GPU-AMD-7600", "AMD Radeon RX 7600 8GB", "AMD", 269.00, "8GB GDDR6, 2048 SP, RDNA 3", 22, "Budget 1080p Radeon."),
        ("GPU-INT-A770", "Intel Arc A770 16GB", "Intel", 279.00, "16GB GDDR6, 4096 ALUs, Xe-HPG", 17, "Value 1440p card with 16GB VRAM."),
    ],
    "RAM": [
        ("RAM-COR-32-6000", "Corsair Vengeance 32GB DDR5-6000", "Corsair", 114.00, "2x16GB, DDR5-6000, CL30, 1.35V", 40, "Enthusiast AM5/Intel DDR5 kit."),
        ("RAM-GSK-32-6400", "G.Skill Trident Z5 32GB DDR5-6400", "G.Skill", 139.00, "2x16GB, DDR5-6400, CL32, RGB", 26, "High-speed RGB DDR5 kit."),
        ("RAM-KIN-16-5600", "Kingston Fury Beast 16GB DDR5-5600", "Kingston", 59.00, "2x8GB, DDR5-5600, CL36", 55, "Affordable DDR5 starter kit."),
        ("RAM-COR-64-5600", "Corsair Vengeance 64GB DDR5-5600", "Corsair", 199.00, "2x32GB, DDR5-5600, CL40", 18, "High-capacity kit for creators."),
        ("RAM-GSK-32-3600", "G.Skill Ripjaws V 32GB DDR4-3600", "G.Skill", 74.00, "2x16GB, DDR4-3600, CL18", 47, "Proven DDR4 kit for AM4/LGA1200."),
        ("RAM-CRU-16-3200", "Crucial 16GB DDR4-3200", "Crucial", 39.00, "2x8GB, DDR4-3200, CL16", 60, "Reliable budget DDR4 kit."),
    ],
    "SSD": [
        ("SSD-SAM-990-2TB", "Samsung 990 Pro 2TB NVMe", "Samsung", 169.00, "PCIe 4.0, 7450/6900 MB/s, M.2 2280", 33, "Flagship Gen4 NVMe SSD."),
        ("SSD-WD-SN850-1TB", "WD Black SN850X 1TB NVMe", "Western Digital", 89.00, "PCIe 4.0, 7300 MB/s read, M.2 2280", 44, "Top gaming Gen4 SSD."),
        ("SSD-CRU-T700-2TB", "Crucial T700 2TB Gen5 NVMe", "Crucial", 239.00, "PCIe 5.0, 12400 MB/s read, M.2 2280", 10, "Cutting-edge Gen5 SSD."),
        ("SSD-SAM-870-1TB", "Samsung 870 EVO 1TB SATA", "Samsung", 79.00, "SATA III, 560 MB/s, 2.5-inch", 52, "Dependable SATA SSD."),
        ("SSD-CRU-MX500-500", "Crucial MX500 500GB SATA", "Crucial", 44.00, "SATA III, 560 MB/s, 2.5-inch", 61, "Budget 2.5-inch SSD."),
        ("HDD-SEA-BARR-4TB", "Seagate BarraCuda 4TB HDD", "Seagate", 84.00, "3.5-inch, 5400 RPM, SATA, 256MB cache", 29, "High-capacity mechanical storage."),
        ("HDD-WD-RED-8TB", "WD Red Plus 8TB NAS HDD", "Western Digital", 169.00, "3.5-inch, 5640 RPM, CMR, NAS-rated", 15, "NAS-optimized hard drive."),
    ],
    "MBD": [
        ("MBD-ASU-B650E-F", "ASUS ROG Strix B650E-F Gaming", "ASUS", 259.00, "AM5, DDR5, PCIe 5.0, ATX, Wi-Fi 6E", 15, "Feature-rich AM5 ATX board."),
        ("MBD-MSI-B650-T", "MSI MAG B650 Tomahawk Wi-Fi", "MSI", 219.00, "AM5, DDR5, PCIe 4.0, ATX, Wi-Fi 6E", 20, "Robust VRM mid-range AM5 board."),
        ("MBD-GIG-X670E", "Gigabyte X670E Aorus Master", "Gigabyte", 449.00, "AM5, DDR5, PCIe 5.0, E-ATX, Wi-Fi 6E", 7, "High-end overclocking AM5 board."),
        ("MBD-ASU-Z790-P", "ASUS Prime Z790-P Wi-Fi", "ASUS", 229.00, "LGA1700, DDR5, PCIe 5.0, ATX, Wi-Fi 6", 18, "Solid Intel Z790 ATX board."),
        ("MBD-MSI-B760M", "MSI Pro B760M-A Wi-Fi", "MSI", 139.00, "LGA1700, DDR5, mATX, Wi-Fi 6", 26, "Compact value Intel board."),
        ("MBD-ASR-B550M", "ASRock B550M Pro4", "ASRock", 99.00, "AM4, DDR4, PCIe 4.0, mATX", 34, "Affordable AM4 micro-ATX board."),
    ],
    "PSU": [
        ("PSU-SEA-GX850", "Seasonic Focus GX-850 850W", "Seasonic", 129.00, "850W, 80+ Gold, fully modular, ATX 3.0", 27, "Reliable 80+ Gold PSU."),
        ("PSU-COR-RM1000", "Corsair RM1000e 1000W", "Corsair", 159.00, "1000W, 80+ Gold, fully modular, ATX 3.0", 19, "High-wattage PSU with PCIe 5.0."),
        ("PSU-EVG-650G", "EVGA SuperNOVA 650 GT 650W", "EVGA", 89.00, "650W, 80+ Gold, fully modular", 31, "Compact mid-power PSU."),
        ("PSU-BEQ-750", "be quiet! Pure Power 12 M 750W", "be quiet!", 109.00, "750W, 80+ Gold, modular, ATX 3.0", 23, "Quiet and efficient 750W PSU."),
        ("PSU-COR-SF750", "Corsair SF750 750W SFX", "Corsair", 149.00, "750W, 80+ Platinum, SFX, modular", 12, "Premium SFX PSU for ITX builds."),
    ],
    "CASE": [
        ("CASE-LIA-O11D", "Lian Li O11 Dynamic EVO", "Lian Li", 169.00, "Mid-tower, dual-chamber, tempered glass, E-ATX", 16, "Popular showcase chassis."),
        ("CASE-FRA-NORTH", "Fractal Design North", "Fractal Design", 139.00, "Mid-tower, wood front, mesh, ATX", 21, "Stylish airflow-focused case."),
        ("CASE-NZX-H7F", "NZXT H7 Flow", "NZXT", 129.00, "Mid-tower, high airflow mesh, ATX", 24, "Clean-look airflow mid-tower."),
        ("CASE-COR-4000D", "Corsair 4000D Airflow", "Corsair", 94.00, "Mid-tower, mesh front, ATX", 30, "Best-selling airflow case."),
        ("CASE-COO-NR200", "Cooler Master NR200P", "Cooler Master", 109.00, "Mini-ITX, SFF, tempered glass", 14, "Compact ITX SFF case."),
    ],
    "COOL": [
        ("COOL-NOC-D15", "Noctua NH-D15 chromax.black", "Noctua", 109.00, "Dual-tower air, 2x140mm fans, 165W TDP", 22, "Legendary high-end air cooler."),
        ("COOL-ARC-LF360", "Arctic Liquid Freezer III 360", "Arctic", 79.00, "360mm AIO, 3x120mm, VRM fan", 26, "High-value 360mm liquid cooler."),
        ("COOL-COR-H150", "Corsair iCUE H150i Elite 360", "Corsair", 189.00, "360mm AIO, RGB, LCD-ready", 13, "Premium RGB 360mm AIO."),
        ("COOL-BEQ-DR4", "be quiet! Dark Rock Pro 4", "be quiet!", 89.00, "Dual-tower air, 250W TDP, quiet", 19, "Silent high-performance air cooler."),
        ("COOL-DEE-AK400", "DeepCool AK400", "DeepCool", 34.00, "Single-tower air, 120mm, 220W TDP", 40, "Excellent budget air cooler."),
    ],
    "MON": [
        ("MON-LG-27GP850", "LG UltraGear 27GP850-B 27 inch", "LG", 379.00, "27 inch QHD, IPS, 165Hz, 1ms, G-Sync", 17, "Fast 1440p IPS gaming monitor."),
        ("MON-SAM-G7-32", "Samsung Odyssey G7 32 inch", "Samsung", 549.00, "32 inch QHD, VA, 240Hz, 1ms, curved", 9, "High-refresh curved gaming monitor."),
        ("MON-DEL-S2722QC", "Dell S2722QC 27 inch 4K", "Dell", 319.00, "27 inch 4K UHD, IPS, 60Hz, USB-C 65W", 14, "Sharp 4K productivity monitor."),
        ("MON-AOC-24G2", "AOC 24G2 24 inch", "AOC", 149.00, "24 inch FHD, IPS, 144Hz, 1ms", 33, "Affordable 1080p esports monitor."),
        ("MON-ASU-PG27AQDM", "ASUS ROG Swift PG27AQDM 27 inch", "ASUS", 899.00, "27 inch QHD, OLED, 240Hz, 0.03ms", 5, "Premium OLED gaming monitor."),
    ],
    "KBD": [
        ("KBD-KEY-V3MAX", "Keychron V3 Max", "Keychron", 99.00, "TKL, wireless, hot-swap, gasket mount", 28, "Customizable wireless mechanical board."),
        ("KBD-COR-K70", "Corsair K70 RGB Pro", "Corsair", 139.00, "Full-size, Cherry MX, RGB, USB pass", 20, "Durable gaming keyboard."),
        ("KBD-LOG-G915", "Logitech G915 TKL", "Logitech", 199.00, "TKL, low-profile, wireless, RGB", 11, "Premium low-profile wireless board."),
        ("KBD-RAZ-HUNT", "Razer Huntsman V3 Pro", "Razer", 189.00, "Full-size, analog optical, RGB", 13, "Analog optical gaming keyboard."),
        ("KBD-RK-61", "Royal Kludge RK61", "Royal Kludge", 45.00, "60%, wireless, hot-swap, RGB", 37, "Budget 60% mechanical board."),
    ],
    "MOU": [
        ("MOU-LOG-GPXSW", "Logitech G Pro X Superlight 2", "Logitech", 159.00, "Wireless, 60g, HERO 2 sensor, 32K DPI", 24, "Esports wireless mouse."),
        ("MOU-RAZ-VIPERV3", "Razer Viper V3 Pro", "Razer", 149.00, "Wireless, 54g, Focus Pro 35K", 18, "Ultralight competitive mouse."),
        ("MOU-GLO-MODEL-O", "Glorious Model O 2 Wireless", "Glorious", 79.00, "Wireless, 59g, BAMF 2.0 sensor", 29, "Lightweight honeycomb mouse."),
        ("MOU-COR-M65", "Corsair M65 RGB Ultra", "Corsair", 59.00, "Wired, FPS, adjustable weight, 26K DPI", 26, "FPS-focused wired mouse."),
        ("MOU-LOG-MX3S", "Logitech MX Master 3S", "Logitech", 99.00, "Wireless, ergonomic, 8K DPI, quiet", 31, "Productivity ergonomic mouse."),
    ],
    "PRE": [
        ("PRE-STARTER-R5", "Depot Starter - Ryzen 5 / RTX 4060", "PC Parts Depot", 999.00, "R5 7600, RTX 4060, 16GB DDR5, 1TB NVMe", 10, "Entry 1080p gaming desktop."),
        ("PRE-GAMER-R7", "Depot Gamer - Ryzen 7 / RTX 4070S", "PC Parts Depot", 1599.00, "R7 7800X3D, RTX 4070 SUPER, 32GB DDR5, 2TB", 7, "Mainstream 1440p gaming desktop."),
        ("PRE-PRO-I7", "Depot Pro - Core i7 / RTX 4080S", "PC Parts Depot", 2299.00, "i7-14700K, RTX 4080 SUPER, 32GB DDR5, 2TB", 5, "High-end gaming and creator PC."),
        ("PRE-ULTRA-I9", "Depot Ultra - Core i9 / RTX 4090", "PC Parts Depot", 3499.00, "i9-14900K, RTX 4090, 64GB DDR5, 4TB", 3, "No-compromise 4K powerhouse."),
        ("PRE-WORK-R9", "Depot Workstation - Ryzen 9", "PC Parts Depot", 2799.00, "R9 7950X, RTX 4080 SUPER, 64GB DDR5, 4TB", 4, "Multithreaded content-creation rig."),
    ],
}


def esc(value: str) -> str:
    return value.replace("'", "''")


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.normpath(os.path.join(here, "..", "src", "assets", "seed.sql"))

    lines = []
    lines.append("-- " + "=" * 74)
    lines.append("-- PC Parts Depot - demo inventory seed data (Oracle Database 21c)")
    lines.append("-- " + "-" * 74)
    lines.append("-- Run AFTER schema.sql, as the application schema/user.")
    lines.append("-- Idempotent: clears existing rows before inserting.")
    lines.append("-- " + "=" * 74)
    lines.append("")
    lines.append("DELETE FROM PRODUCTS;")
    lines.append("DELETE FROM CATEGORIES;")
    lines.append("")

    for code, name, desc in CATEGORIES:
        lines.append(
            f"INSERT INTO CATEGORIES (CODE, NAME, DESCRIPTION) VALUES "
            f"('{code}', '{esc(name)}', '{esc(desc)}');"
        )
    lines.append("")

    pid = 0
    for code, _, _ in CATEGORIES:
        for sku, pname, brand, price, specs, stock, pdesc in PRODUCTS[code]:
            pid += 1
            lines.append(
                "INSERT INTO PRODUCTS (ID, SKU, NAME, CATEGORY_CODE, BRAND, PRICE, "
                "SPECS, STOCK, IMAGE_URL, DESCRIPTION) VALUES ("
                f"{pid}, '{esc(sku)}', '{esc(pname)}', '{code}', '{esc(brand)}', "
                f"{price:.2f}, '{esc(specs)}', {stock}, '/images/placeholder.svg', "
                f"'{esc(pdesc)}');"
            )
        lines.append("")

    lines.append("COMMIT;")
    lines.append("")

    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    print(f"Wrote {pid} products across {len(CATEGORIES)} categories to {out_path}")


if __name__ == "__main__":
    main()
