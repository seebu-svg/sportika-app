"""Bundle credited sports photography; standard library only."""
from pathlib import Path
from urllib.request import Request, urlopen

SOURCES = {
    'cricket': 'https://images.unsplash.com/photo-1594470117722-de4b9a02ebed?fm=jpg&fit=crop&w=1200&q=78',
    'padel': 'https://images.unsplash.com/photo-1658491830143-72808ca237e3?fm=jpg&fit=crop&w=1200&q=78',
    'futsal': 'https://images.pexels.com/photos/29388472/pexels-photo-29388472.jpeg?auto=compress&cs=tinysrgb&w=1200',
    'badminton': 'https://images.pexels.com/photos/2202685/pexels-photo-2202685.jpeg?auto=compress&cs=tinysrgb&w=1200',
}

if __name__ == '__main__':
    destination = Path(__file__).resolve().parents[1] / 'assets/images/sports'
    destination.mkdir(parents=True, exist_ok=True)
    for sport, url in SOURCES.items():
        with urlopen(Request(url, headers={'User-Agent': 'Sportika/1.0'}), timeout=30) as response:
            data = response.read()
        if not data.startswith(b'\xff\xd8\xff'):
            raise ValueError(f'{sport}: expected JPEG image')
        temporary = destination / f'{sport}.jpg.tmp'
        temporary.write_bytes(data)
        temporary.replace(destination / f'{sport}.jpg')
        print(f'{sport}: {len(data):,} bytes')
