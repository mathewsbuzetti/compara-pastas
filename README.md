# 🔄 Comparador de Pastas - PowerShell

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Mathews_Buzetti-blue)](https://www.linkedin.com/in/mathewsbuzetti)
![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat-square&logo=powershell&logoColor=white)
![Status](https://img.shields.io/badge/Status-Production-green?style=flat-square)
![Documentation](https://img.shields.io/badge/Documentation-Technical-blue?style=flat-square)

**Aplica-se a:** ✔️ Windows 10/11 ✔️ Windows Server 2016/2019/2022

## 📋 Metadados

| Metadado | Descrição |
|----------|-----------|
| **Título** | Comparador de Pastas - Versão Aprimorada |
| **Assunto** | Comparação de arquivos entre pastas/diretórios |
| **Versão** | 1.0.0 |
| **Data** | 05/03/2025 |
| **Autor** | Mathews Buzetti |
| **Tags** | `powershell`, `file-comparison`, `directory-sync`, `reporting` |

## 📊 Visualização do Relatório Interativo

<p align="center">
  <a href="[https://exemplo-relatorio-comparador.netlify.app](https://mathewsbuzetti.github.io/powershell-folder-comparison-tool/)" target="_blank">
    <img src="https://img.shields.io/badge/Visualizar%20Demo-Relatório%20HTML%20Interativo-brightgreen?style=for-the-badge&logo=html5" alt="Visualizar Demo" width="350">
  </a>
</p>

![image](https://github.com/user-attachments/assets/aaff75a0-b60d-4525-88ed-1e21955b0ca8)

![image](https://github.com/user-attachments/assets/fb708e18-e50e-41c5-9aa9-c3f4e175f138)

![image](https://github.com/user-attachments/assets/5693de2b-9605-43e0-87a8-793e80a589e0)


## 📋 Índice

1. [Metadados](#-metadados)
2. [Screenshots](#-screenshots)
3. [Funcionalidades](#-funcionalidades)
4. [Pré-requisitos](#-pré-requisitos)
5. [Como Usar](#-como-usar)
6. [Configuração de Múltiplas Pastas](#-configuração-de-múltiplas-pastas)
7. [Parâmetros do Script](#-parâmetros-do-script)
8. [Tratamento de Erros e Feedback](#-tratamento-de-erros-e-feedback)
9. [Relatório HTML](#-relatório-html)
10. [Versionamento](#-Versionamento)

## 💻 Funcionalidades

### 📊 Principais Recursos
* Comparação eficiente de dois diretórios
* Processamento paralelo para melhor desempenho em grandes estruturas de arquivos
* Relatório HTML interativo com gráficos, estatísticas e tabela de arquivos
* Controle de progresso visual em tempo real
* Suporte para caminhos longos
* Tratamento otimizado para grandes volumes de arquivos
* Rastreamento de tempo e estatísticas de processamento
* Sistema de checklist para acompanhamento de sincronização

### ⚙️ Modos de Processamento
* **Paralelo**: Utiliza múltiplos threads para melhor desempenho em sistemas modernos
* **Sequencial**: Compatível com ambientes mais restritos como PowerShell ISE

### 📈 Relatório HTML Avançado
* Gráficos de distribuição por tamanho de arquivo
* Gráficos de extensões mais comuns
* Distribuição por subpastas
* Tabela completa dos arquivos com filtros e paginação
* Sistema de progresso para acompanhamento de sincronização
* Estatísticas detalhadas do resultado da comparação

## 📋 Pré-requisitos

* Windows 10/11 ou Windows Server 2016/2019/2022
* PowerShell 5.1 ou superior
* Permissões de leitura nas pastas a serem comparadas
* Navegador moderno para visualizar o relatório HTML (Chrome, Edge, Firefox)
* PowerShell 7+ para processamento paralelo (opcional, mas recomendado para melhor performance)

## 🚀 Como Usar

### 1. Configuração Básica

1. Baixe o script: 
  
[![Download Script](https://img.shields.io/badge/Download%20Script%20Start%2FStop-blue?style=flat-square&logo=powershell)](https://github.com/mathewsbuzetti/powershell-folder-comparison-tool/blob/main/Script/Compare-FolderStructures.ps1)
   
3. Abra o script em um editor de texto como Notepad++ ou VSCode
4. Localize a seção de configuração no final do script:

```powershell
# Configurações de exemplo (podem ser alteradas conforme necessário)
$outputDir = "C:\temp\COMPARAÇÕES"  # Pasta onde serão salvos os relatórios

# Definir os pares de pastas para comparação
$folderPairs = @(
    # Par 1: Documentos Rede vs Documentos Local
    @{
        Folder1 = "\\servidor\compartilhamento\Documentos"
        Folder2 = "D:\Backup\Documentos"
    }
)

# Executar a comparação com geração automática de nomes
Compare-FolderPairs -FolderPairs $folderPairs -OutputDir $outputDir
```

4. Modifique as variáveis:
   - `$outputDir`: Pasta onde os relatórios HTML serão salvos
   - `$folderPairs`: Caminhos das pastas que deseja comparar
     - `Folder1`: Pasta de origem (arquivos que serão verificados)
     - `Folder2`: Pasta de destino (onde será procurado se o arquivo existe)

### 2. Execução do Script

**Método 1: PowerShell ISE ou Console**
1. Abra o PowerShell ISE ou o Console do PowerShell
2. Navegue até a pasta do script:
   ```powershell
   cd "C:\Caminho\Para\Pasta\Do\Script"
   ```
3. Execute o script:
   ```powershell
   .\Comparador_Arquivos_Rede_v2.ps1
   ```

**Método 2: Clique com botão direito**
1. Clique com o botão direito no script
2. Selecione "Executar com PowerShell"

### 3. Resultados
- O script mostrará o progresso em tempo real no console
- Ao concluir, um relatório HTML será gerado na pasta de saída configurada
- O relatório será aberto automaticamente no navegador padrão

## 🔄 Configuração de Múltiplas Pastas

Para comparar múltiplos pares de pastas em uma única execução, modifique a configuração `$folderPairs` adicionando mais itens ao array:

```powershell
# Definir os pares de pastas para comparação
$folderPairs = @(
    # Par 1: Documentos Rede vs Documentos Local
    @{
        Folder1 = "\\servidor\compartilhamento\Documentos"
        Folder2 = "D:\Backup\Documentos"
    },
    # Par 2: Imagens Rede vs Imagens Local
    @{
        Folder1 = "\\servidor\compartilhamento\Imagens"
        Folder2 = "D:\Backup\Imagens"
    },
    # Par 3: Projetos Rede vs Projetos Local
    @{
        Folder1 = "\\servidor\compartilhamento\Projetos"
        Folder2 = "D:\Backup\Projetos" 
    }
)
```

Cada par de pastas gerará um relatório HTML separado na pasta de saída configurada.

## 🔧 Parâmetros do Script

### Função Compare-FolderPairs

| Parâmetro | Descrição | Valores Padrão |
|-----------|-----------|----------------|
| `FolderPairs` | Array de objetos com pares Folder1 e Folder2 | Obrigatório |
| `OutputDir` | Diretório onde serão salvos os relatórios | "C:\temp" |
| `HandleLongPaths` | Habilita suporte para caminhos longos | $false |
| `UseParallel` | Utiliza processamento paralelo para melhor desempenho | $true |
| `MaxThreads` | Número máximo de threads para processamento paralelo | Número de núcleos do processador |

### Função Compare-Folders

| Parâmetro | Descrição | Valores Padrão |
|-----------|-----------|----------------|
| `Folder1Path` | Caminho da pasta de origem | Obrigatório |
| `Folder2Path` | Caminho da pasta de destino | Obrigatório |
| `HTMLReport` | Caminho para o arquivo HTML de relatório | "" (gerado automaticamente) |
| `HandleLongPaths` | Habilita suporte para caminhos longos | $false |
| `UseParallel` | Utiliza processamento paralelo para melhor desempenho | $true |
| `MaxThreads` | Número máximo de threads para processamento paralelo | 0 (usa o padrão global) |
| `ShowDebug` | Exibe mensagens de debug durante a execução | $false |

## ⚠️ Tratamento de Erros e Feedback

O script fornece feedback visual em tempo real com cores diferentes:
- 🟦 **Azul/Ciano**: Informações do processo
- 🟩 **Verde**: Operações concluídas com sucesso
- 🟨 **Amarelo**: Avisos e alertas não críticos
- 🟥 **Vermelho**: Erros críticos que impediram a execução

Erros comuns que são tratados automaticamente:
- Pastas inacessíveis ou inexistentes
- Problemas de permissão em arquivos
- Caminhos muito longos (quando HandleLongPaths é ativado)
- Limitações do PowerShell ISE (modo paralelo é desativado automaticamente)

## 📊 Relatório HTML

O relatório HTML gerado inclui:

1. **Cabeçalho com Informações Gerais**
   - Pastas comparadas (origem e destino)
   - Data e hora da comparação
   - Estatísticas gerais (arquivos analisados, arquivos ausentes, tamanho total)

2. **Resumo da Análise**
   - Total de arquivos analisados
   - Arquivos ausentes na pasta de destino
   - Tamanho total dos arquivos ausentes
   - Tempo total da análise

3. **Visualizações Gráficas**
   - Distribuição por tamanho de arquivo
   - Top 10 extensões mais comuns
   - Top 5 subpastas com mais arquivos ausentes

4. **Sistema de Progresso de Sincronização**
   - Barra de progresso visual
   - Contadores de arquivos pendentes e concluídos
   - Sistema de checklist para marcar arquivos já processados

5. **Tabela Detalhada**
   - Lista completa de todos os arquivos ausentes
   - Filtros e ordenação por qualquer coluna
   - Paginação para melhor navegação
   - Botões para copiar caminhos

## 🔄 Versionamento

- Versão: 1.0.0
- Última atualização: 05/03/2025
