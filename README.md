# Blackjack

Cette application Elixir propose un agent de Blackjack que l’on peut exécuter en ligne de commande. Suivez les étapes ci‑dessous pour lancer le programme à l’aide de Docker.

## Prérequis
- Docker installé (version 24+ recommandée).
- Accès au dossier `blackjack` de ce dépôt.

## Configuration du docker
- Si on veut jouer avec un autre docker local. Il faut préciser son adresse dans le Dockerfile :
  ENV BLACKJACK_SERVER_URL=http://host.docker.internal:3000

## Construire l’image
Depuis le dossier `blackjack`, exécutez:

```bash
docker build -t blackjack-app .
```

Cette commande installe les dépendances Mix et compile l’application en environnement de production.

## Lancer le jeu
Toujours depuis le dossier `blackjack`:

```bash
docker run -it --rm blackjack-app
```

Confirmer l'installation de Hex : Y

- `-it` garde la session interactive pour répondre aux questions du jeu.
- `--rm` supprime le conteneur à la fin de la partie (optionnel).

Au démarrage, l’application vous demande de choisir la version d’agent (`0` à `3`). Entrez le numéro souhaité pour commencer une partie contre l’agent correspondant.

> Note : En roulant dans le docker, il faut absolument aller chercher les .csv directement dans le conteneur.