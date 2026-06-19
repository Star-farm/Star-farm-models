import numpy as np
import pandas as pd

# =========================================================
# PARAMÈTRES DE FILTRAGE
# =========================================================
DATE_DEBUT_SIMULATION = "2010-01-01" 
DATE_DEBUT_EXTRACTION = "2010-01-01" 
DATE_FIN_EXTRACTION   = "2020-12-31" 
STATIONS_CIBLEES = [] # Laissez vide pour toutes les stations, ou mettez des noms

# =========================================================
# 1. CHARGEMENT DES DONNÉES
# =========================================================
print("Chargement du fichier NPY...")
donnees = np.load('SWI_Projections_P90.npy', allow_pickle=True, encoding='latin1')
contenu = donnees.item()

coordonnees = {}
series_temporelles = {}
stations_ciblees_clean = [s.strip().lower() for s in STATIONS_CIBLEES]

# =========================================================
# 2. NETTOYAGE (AVEC FILTRE ANTI-DATES CACHÉES)
# =========================================================
print("Extraction des données de salinité...")
for station, valeurs in contenu.items():
    
    station_clean = str(station).strip().lower()
    if stations_ciblees_clean and station_clean not in stations_ciblees_clean: continue
        
    if isinstance(valeurs, dict): liste_valeurs = list(valeurs.values())
    elif hasattr(valeurs, 'tolist'): liste_valeurs = valeurs.tolist()
    else: liste_valeurs = list(valeurs)
        
    # A. Coordonnées GPS
    coords = [None, None]
    for item in liste_valeurs:
        if isinstance(item, (list, tuple, np.ndarray)) and len(item) == 2:
            if all(isinstance(x, (int, float, np.number)) for x in item):
                # Les coordonnées GPS sont généralement < 200 (Long/Lat)
                if abs(item[0]) < 200 and abs(item[1]) < 200:
                    coords = list(item)
                    break 
    coordonnees[station_clean] = coords
        
    # B. Extraction de la vraie salinité (Filtre < 100)
    valeurs_numeriques = []
    for val in liste_valeurs:
        if isinstance(val, (list, tuple, np.ndarray)) and len(val) == 2 and list(val) == coords:
            continue
            
        if isinstance(val, (int, float, np.number)) and not isinstance(val, bool):
            # FILTRE MAGIQUE : On ignore les "dates Matlab" géantes (> 100)
            if float(val) < 100.0:
                valeurs_numeriques.append(float(val))
            
        elif isinstance(val, (list, tuple, np.ndarray)):
            for sous_val in val:
                if isinstance(sous_val, (int, float, np.number)) and not isinstance(sous_val, bool):
                    # Même filtre ici
                    if float(sous_val) < 100.0:
                        valeurs_numeriques.append(float(sous_val))
    
    series_temporelles[station_clean] = np.round(valeurs_numeriques, 2)

# =========================================================
# 3. CRÉATION DES FICHIERS
# =========================================================
df_coords = pd.DataFrame.from_dict(coordonnees, orient='index', columns=['Latitude', 'Longitude'])
df_coords.index.name = 'Station'
df_coords.to_csv('stations_coordonnees.csv')

df_series = pd.DataFrame({k: pd.Series(v) for k, v in series_temporelles.items()})

try:
    if len(df_series) > 0:
        index_dates = pd.date_range(start=DATE_DEBUT_SIMULATION, periods=len(df_series), freq='D')
        df_series.index = index_dates
        df_series.index.name = 'Date'
        df_series_filtre = df_series.loc[DATE_DEBUT_EXTRACTION:DATE_FIN_EXTRACTION]
    else:
        df_series_filtre = df_series
except Exception:
    df_series_filtre = df_series

df_series_filtre.to_csv('salinite_timeseries_legere.csv')
print(f"-> Fichier 'salinite_timeseries_legere.csv' généré ! Vérifiez si les chiffres ont du sens (généralement entre 0 et 40 max).")
