Atuação: Engenheiro de Level Design no Godot 4.6.
Objetivo: Estruturar a cena components/mapa/pista_corrida.tscn para um sistema de corrida de cavalos.

Especificações de Hierarquia e Cena:

GridMap & MeshLibrary: Oriente a criação de uma MeshLibrary onde as peças de pista (retas, curvas, rampas) estejam na Physics Layer 2 (Blocos). Gere um script de utilidade para alinhar automaticamente as colisões dos tiles ao StaticBody3D de cada mesh.

Track Logic (Path3D): Implemente um nó Path3D que siga o centro da pista.

Crie um script que gere automaticamente nós Area3D (Checkpoints) ao longo desse caminho em intervalos regulares ou em curvas críticas.

O script deve nomear os checkpoints sequencialmente (Checkpoint_01, Checkpoint_02) para facilitar a validação da volta.

Detecção de Terreno (Lama): Projete um sistema de "Material Detection".

Utilize Area3D sobrepostas a tiles de lama.

Desafio Técnico: Em vez de sinais individuais, implemente um sistema onde a Area3D da lama altere um metadado (set_meta("terrain_type", "mud")) que o RayCast3D de suspensão do cavalo possa ler em tempo real.

Spawn System (Lucky Blocks):

Defina uma estrutura de Marker3D dentro de um Node chamado LuckyBlockSpawners.

Escreva uma função que instancie o lucky_block.tscn nesses marcadores, garantindo que o RayCast de detecção de chão ignore a Layer 4 (Cavalo) para evitar spawns inválidos.

Visual & Shaders:

Integre o sky.gdshader existente.

Configure o WorldEnvironment para que a névoa (fog) oculte o carregamento de chunks distantes do GridMap, otimizando a performance para o MVP.

Output: Forneça a estrutura da árvore de nós da cena e os scripts GDScript 2.0 para a geração automática dos checkpoints via Path3D.
