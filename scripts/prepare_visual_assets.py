"""Reproduce project-authored cosmetic maps and illustrative Mars dust transport.

Requires NumPy and Pillow during development only. Runtime uses bundled PNGs.
No elevation/source imagery is read or changed. Normal RGB encodes X, Z, Up;
alpha is roughness. The RGB extinction fit is artistic, not measured weather.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "planetary_map/visuals/assets"


def detail_map(name, seed, rock=False):
    n = 512
    rng = np.random.default_rng(seed)
    frequencies = np.fft.fftfreq(n)
    x, y = np.meshgrid(frequencies, frequencies)
    spectrum = np.fft.fft2(rng.normal(size=(n, n)))
    radius = np.sqrt(x*x + y*y)
    broad = np.fft.ifft2(spectrum * np.exp(-(radius / (0.045 if rock else 0.12))**2)).real
    broad /= max(broad.std(), 1e-6)
    grains = rng.normal(size=(n, n))
    height = broad * (0.7 if rock else 0.3) + grains * (0.10 if rock else 0.17)
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * (1.2 if rock else 0.7)
    dz = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * (1.2 if rock else 0.7)
    normal = np.stack((-dx, -dz, np.ones_like(dx)), -1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    rough = np.clip((0.87 if rock else 0.96) + broad * 0.035, 0.73, 1.0)
    packed = np.concatenate((normal * 0.5 + 0.5, rough[..., None]), -1)
    Image.fromarray(np.uint8(np.clip(packed, 0, 1)*255)).save(OUT / name)


def transport():
    w, h = 256, 128
    mu, altitude = np.meshgrid(np.linspace(-1, 1, w), np.linspace(0, 85000, h))
    radius = 3396190.0 + altitude
    top = 3396190.0 + 85000
    distance = -radius*mu + np.sqrt(np.maximum(radius**2*mu**2-radius**2+top**2, 0))
    optical = np.zeros_like(distance)
    for i in range(64):
        t = distance*(i+0.5)/64
        height = np.sqrt(radius**2 + t*t + 2*radius*t*mu)-3396190.0
        optical += np.exp(-np.maximum(height, 0)/10500)*distance/64*0.000085
    intersects_ground = (mu < 0) & (radius**2*(1-mu*mu) < 3396190.0**2)
    rgb = np.exp(-optical[..., None]*np.array([0.65, 0.87, 1.3]))
    rgb[intersects_ground] = 0
    diffuse = 0.25 + 0.75*np.sqrt(np.maximum(mu, 0))
    image = np.concatenate((rgb, diffuse[..., None]), -1)
    Image.fromarray(np.uint8(np.clip(image, 0, 1)*255)).save(OUT / "dust_transport.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    detail_map("sand_normal_roughness.png", 7462)
    detail_map("rock_normal_roughness.png", 8723, rock=True)
    transport()
    print("Prepared three illustrative visual maps; geographic data unchanged.")
