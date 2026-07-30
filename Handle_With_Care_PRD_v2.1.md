# PRD – Handle With Care
**Versão:** 2.1 (Consolidada + Física Detalhada do Pacote)  
**Data:** 30 de Julho de 2026  
**Status:** Pronto para implementação  

---

## 1. Visão do Produto

### 1.1 Conceito Central
**Handle With Care** é um platformer 2D de 8 bits no qual o jogador deve carregar um **pacote extremamente instável e reativo** até a Zona de Entrega no final de cada fase.

O objetivo é diferente do Level Devil (que é apenas chegar na porta). Aqui o objetivo é:

> **Entregar o pacote intacto na Zona de Entrega.**

O pacote possui personalidade e física própria. Ele reage de forma exagerada e engraçada a pulos, paradas bruscas, quedas, perigos e tempo. As falhas vêm tanto das armadilhas do nível quanto das reações do próprio pacote, gerando alto potencial de viralização (fails legíveis e engraçados em poucos segundos).

### 1.2 Fantasy do Jogador
“Eu só preciso entregar esse maldito pacote... por que ele está se comportando assim?!”

### 1.3 Pilares de Design
1. Clareza imediata do objetivo
2. Fails engraçados e legíveis em menos de 2 segundos
3. Segunda camada de troll (o jogo pune a adaptação do jogador)
4. Níveis curtos (30–90 segundos por tentativa ideal)
5. Retry quase instantâneo
6. Progressão de loucura (cada fase tem uma regra especial própria)
7. Estética 8-bit consistente
8. Feedback sonoro completo em todas as ações e situações

### 1.4 Plataformas-Alvo
- Web (Poki + site próprio)
- Steam (PC – Windows prioritário)
- Mobile nativo fica fora do escopo da versão 1.0

---

## 2. Decisões de Design Confirmadas

- Nome oficial: **Handle With Care**
- O pacote é sempre **grudado** no personagem (não é empurrado nem solto manualmente)
- O pacote acompanha a posição do personagem com offset e possui estados + física própria
- 10 fases, cada uma com tema e “loucura” própria
- Menu simples com Novo Jogo, Continuar, Seleção de Fases, Opções, Créditos e Sair
- Save local automático
- Sons para todas as ações e situações relevantes

---

## 3. Gameplay Core

### 3.1 Objetivo
Levar o pacote até a Zona de Entrega sem que ele seja destruído, fuja ou entre em estado crítico irreversível.

### 3.2 Controles
**Desktop:**
- A / Seta Esquerda → Andar para esquerda
- D / Seta Direita → Andar para direita
- W / Seta Cima / Espaço → Pular
- R → Restart rápido da fase atual
- Esc → Pausar

**Mobile (futuro):** botões virtuais.

### 3.3 Condições de Falha
- Pacote destruído (explosão, spike, queda em buraco, etc.)
- Pacote fugiu da tela
- Jogador morreu
- Pacote permaneceu em estado crítico por tempo demais

### 3.4 Condição de Vitória da Fase
Entregar o pacote dentro da Zona de Entrega.

### 3.5 Restart
Quase instantâneo. A fase reinicia do início (sem checkpoints intermediários na v1).

---

## 4. Física Detalhada do Pacote (Grudado)

### 4.1 Princípios Gerais
- O pacote é **sempre grudado** no personagem.
- Ele **não** possui collider próprio com plataformas (para evitar stuck e tunneling).
- Ele herda a posição base do personagem e aplica um **offset + comportamento adicional** de acordo com o estado atual.
- Toda a física do pacote é simulada manualmente (kinematic + forças + damping).
- O pacote pode aplicar forças de volta no personagem em certos estados.

### 4.2 Variáveis Principais

```lua
package = {
    offset_x = 8,               -- pixels à frente do personagem
    offset_y = 12,              -- altura em relação aos pés do personagem
    
    stress = 0,                 -- 0 a 100
    stress_max = 100,
    
    current_state = "stable",   -- stable, nervous, panic, heavy, light, explosive, magnetized, sleeping
    
    mass = 1.0,                 -- massa virtual (1.0 = normal)
    shake_intensity = 0,        -- 0 a 1
    vertical_force = 0,         -- força extra no eixo Y
    horizontal_force = 0,       -- força extra no eixo X (pode afetar o player)
    
    velocity_x = 0,
    velocity_y = 0,
    
    explosive_timer = 0,        -- contagem regressiva quando entra em explosive
    panic_impulse_timer = 0,
}
```

### 4.3 Cálculo de Posição a Cada Frame

```text
Posição final do pacote =
    Posição do personagem
  + Offset base (considerando direção que o personagem está olhando)
  + Shake (ruído senoidal)
  + Offset vertical extra (quando leve ou pesado)
  + Impulse residual (quando em pânico)
```

**Pseudocódigo de atualização:**

```lua
local facing = player.facing_right and 1 or -1

local target_x = player.position.x + (package.offset_x * facing)
local target_y = player.position.y + package.offset_y

-- Aplica shake
target_x = target_x + math.sin(time * 40) * package.shake_intensity * 2
target_y = target_y + math.cos(time * 35) * package.shake_intensity * 1.5

-- Aplica forças residuais
package.velocity_x = package.velocity_x * 0.85 + package.horizontal_force
package.velocity_y = package.velocity_y * 0.85 + package.vertical_force

target_x = target_x + package.velocity_x
target_y = target_y + package.velocity_y

-- Suavização
package.position.x = lerp(package.position.x, target_x, 0.35)
package.position.y = lerp(package.position.y, target_y, 0.35)
```

### 4.4 Comportamento Físico por Estado

**Stable (Estável)**
- mass = 1.0
- shake_intensity = 0
- horizontal_force = 0
- vertical_force = 0
- Segue o personagem de forma limpa.

**Nervous (Nervoso)**
- shake_intensity = 0.4 ~ 0.7
- Estresse sobe lentamente
- Leve atraso na resposta (lerp menor)
- Visual: treme

**Panic (Em Pânico)**
- shake_intensity = 1.0
- A cada 0.4~0.7s aplica impulso aleatório:
  - horizontal_force = random(-120, 120)
  - vertical_force = random(80, 160)
- Esses impulsos afetam levemente o personagem (knockback de 15~30%)
- Estresse sobe rápido
- Visual: olhos arregalados + animação de tentativa de fuga

**Heavy (Pesado)**
- mass = 2.2 ~ 2.8
- Reduz velocidade máxima do personagem em ~35%
- Reduz altura do pulo em ~30%
- Offset Y do pacote desce
- Movimento mais arrastado

**Light (Leve)**
- mass = 0.35 ~ 0.5
- vertical_force positivo constante leve (flutua)
- Resposta mais atrasada e flutuante
- Controles do personagem ficam escorregadios
- Offset Y sobe

**Explosive (Explosivo)**
- Ativado quando stress >= 100 ou por trigger de fase
- Inicia explosive_timer (1.2 ~ 1.8 segundos)
- Pisca cada vez mais rápido + beep acelerando + shake aumenta
- Ao zerar o timer → explosão → morte da tentativa

**Magnetized (Magnetizado)**
- Procura hazards em raio de 80~110 pixels
- Aplica força de atração nos hazards em direção ao pacote
- Visual: aura ou partículas

**Sleeping (Dormindo)**
- shake_intensity = 0 e forças zeradas
- Só muda de estado com impacto forte
- Ao acordar → geralmente vai para Nervous ou Panic

### 4.5 Sistema de Estresse (0 a 100)

**Aumenta com:**
- Pulo normal: +4 a +7
- Pulo alto / aterrissagem forte: +12 a +20
- Mudança brusca de direção: +6 a +10
- Queda de altura média/alta: +15 a +30
- Perto de spike/serra: +8 a +15 por segundo
- Estado Panic ativo: +10 a +18 por segundo

**Diminui com:**
- Movimento suave e constante: –4 a –8 por segundo
- Ficar parado no chão sem perigos: –6 por segundo

### 4.6 Interação com o Personagem
- Quando mass > 1.5 → multiplica velocidade e força de pulo do personagem por `1 / mass`
- Quando em Panic → aplica porcentagem das forças no personagem
- O personagem nunca solta o pacote na v1

### 4.7 Condições de Morte do Pacote
- Contato com spike, serra ou hazard letal
- Queda em buraco
- explosive_timer chega a zero
- Sai completamente da tela por tempo demais

### 4.8 Valores Iniciais Recomendados

```lua
STRESS_JUMP = 6
STRESS_HIGH_JUMP = 16
STRESS_LANDING_HEAVY = 18
STRESS_NEAR_HAZARD = 12        -- por segundo
STRESS_DECAY_SAFE = 7          -- por segundo

PANIC_IMPULSE_INTERVAL = 0.55
HEAVY_MASS = 2.5
LIGHT_MASS = 0.4
EXPLOSIVE_TIME = 1.5
MAGNET_RADIUS = 95
```

### 4.9 Ordem de Implementação da Física
1. Pacote grudado simples (só segue o personagem)
2. Sistema de estados + troca visual
3. Shake
4. Sistema de estresse
5. Heavy e Light (afetando o player)
6. Panic com impulsos
7. Explosive
8. Magnetismo
9. Sleeping + acordar
10. Ajuste fino com playtest

---

## 5. Estrutura das 10 Fases

| Fase | Nome             | Loucura Central                                      | Segunda Camada Principal |
|------|------------------|------------------------------------------------------|--------------------------|
| 1    | Tutorial Soft    | Pacote quase estável                                 | Ensino puro              |
| 2    | Jump Scare       | Pacote odeia pulos altos                             | Punição da hesitação + gap que exige pulo alto |
| 3    | Heavy Duty       | Pacote fica pesado em ciclos                         | Ciclo muda no pior momento + parede de spikes |
| 4    | Hot Potato       | Pacote esquenta e explode com o tempo                | Correr demais vs ir devagar demais |
| 5    | Magnet Madness   | Pacote atrai spikes e serras                         | Tentar evitar atrai mais + spike escondido |
| 6    | Gravity Moods    | Gravidade do pacote muda sozinha                     | Mudança no meio do pulo + atraso proposital |
| 7    | Control Freak    | Controles invertidos enquanto carrega o pacote       | Volta ao normal por poucos segundos + inversão só no ar |
| 8    | Sleepy Package   | Pacote dorme e acorda com impactos                   | Ser suave demais vs acordar e entrar em pânico |
| 9    | Mirror World     | Nível espelhado + reações invertidas do pacote       | Memória muscular + seção final não espelhada |
| 10   | Final Delivery   | Combina várias loucuras anteriores                   | Sequência de punições às adaptações mais comuns |

**Duração alvo por tentativa bem-sucedida:** 35–75 segundos.

---

## 6. Menu e Meta-game

### 6.1 Menu Principal
- Novo Jogo (apaga save e começa da Fase 1)
- Continuar (só aparece se existir save)
- Seleção de Fases (fases desbloqueadas)
- Opções (Volume Master, Música, SFX, Tela Cheia, Controles)
- Créditos
- Sair (Desktop/Steam)

### 6.2 Progressão
- Completar uma fase desbloqueia a próxima
- Save automático local
- Após zerar as 10 fases: mensagem especial + rejogar qualquer fase
- Tela de resultado após cada fase (tempo + tentativas + frase engraçada)

---

## 7. Direção de Arte (8-bit)

- Resolução base: 320x180 ou 384x216 (integer scale)
- Paleta limitada (~32–48 cores)
- Visual fofo + ameaçador
- Backgrounds com parallax simples (2–3 camadas)
- UI em pixel art

### 7.1 Especificações de Sprite Sheet

**Personagem (24x24 px):**
- Idle (4–6 frames)
- Run (6–8 frames)
- Jump / Fall / Land
- Death (4–6 frames)
- Variações de Carry (Idle e Run)

**Pacote (16x16 ou 20x20 px):**
- Estável, Nervoso, Pânico, Pesado, Leve, Explosivo, Dormindo, Magnetizado

**Hazards e Props:**
- Spikes, Serras (rotação), plataformas que caem, Zona de Entrega, partículas

**Atlas no Defold:**
- `characters.atlas`
- `hazards.atlas`
- `ui.atlas`
- `particles.atlas`
- Padding + extrude de 1–2px

---

## 8. Áudio

SFX obrigatórios em estilo 8-bit/chiptune para:
- Passos, pulo, aterrissagem, morte do personagem
- Pacote: tremer, grito/pânico, explosão, ficar pesado, ficar leve, dormir, acordar, magnetismo
- Ambiente: spike/serra, plataforma caindo, Zona de Entrega
- UI: navegação, confirmar, voltar
- Música: Menu, Gameplay, Vitória curta, Game Over curto

---

## 9. Requisitos Técnicos

### 9.1 Engine
**Defold** (melhor opção para HTML5 + desktop).

### 9.2 Boas Práticas Defold para Web
- Usar Atlas para quase todos os sprites
- Lógica cinemática + forças manuais no pacote
- 60 FPS estáveis
- Builds pequenas (Compress engine)
- Evitar alocações excessivas
- Testar em Chrome e Firefox
- Seguir guidelines da Poki
- Input Bindings nativos
- Áudio em .ogg
- Cada fase = Collection separada
- Comunicação Player ↔ Package via Messages
- Game Manager para estado global e save

### 9.3 Estrutura de Projeto
```
/main
  /player
  /package
  /hazards
  /levels
  /ui
  /audio
  /fx
/input
/render
```

### 9.4 Save
- LocalStorage (Web)
- Arquivo local (Steam)

### 9.5 Performance
- Restart quase instantâneo
- Loading entre fases < 1 segundo
- 60 FPS estável

---

## 10. Escopo da Versão 1.0

**Incluído:**
- 10 fases completas
- Sistema completo do pacote grudado + física e estados
- Menu + Save/Load
- Áudio completo
- Build Web (Poki + site) + Steam (Windows)
- Suporte a teclado

**Fora de escopo:**
- Multiplayer, Level Editor, Mobile nativo, Cosméticos, Leaderboards, mais de 10 fases

---

## 11. Critérios de Aceite

Uma fase só é aceita quando:
- É possível completá-la de forma justa
- Possui pelo menos 2 momentos claros de segunda camada
- Mortes mais comuns são legíveis em < 2 segundos
- O pacote reage de forma visível e audível
- Restart é instantâneo
- Não existem softlocks
- A loucura da fase é claramente sentida

---

## 12. Riscos e Mitigações

| Risco                          | Mitigação                                      |
|--------------------------------|------------------------------------------------|
| Pacote confuso de controlar    | Feedback visual/sonoro forte + Fase 1 sólida   |
| Fails pouco engraçados         | Playtests frequentes                           |
| Parecer demais com Level Devil | Foco total no pacote como fonte do caos        |
| Build web pesada               | Otimização agressiva de atlas e código         |

---

## 13. Ordem de Implementação Recomendada

1. Projeto Defold + estrutura de pastas
2. Player (movimento + animações)
3. Package grudado + sistema de estados e física
4. Fase 1 completa
5. Menu + Save
6. Transição entre fases
7. Fases 2 a 10
8. Áudio completo
9. Playtests e ajustes
10. Builds finais (Web + Steam)

---

**Fim do PRD Consolidado v2.1**
```
