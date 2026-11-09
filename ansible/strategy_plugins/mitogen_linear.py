# Mitogen (ansible.cfg, strategy) : un interpréteur Python gardé ouvert sur
# l'hôte au lieu d'un relancé à chaque tâche, 6 à 7 fois plus rapide sur le Pi.
# Ce relais évite d'écrire dans ansible.cfg le chemin du site-packages du venv,
# qui change à chaque montée de Python.
from ansible_mitogen.plugins.strategy.mitogen_linear import StrategyModule  # noqa: F401
