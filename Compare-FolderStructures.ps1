# Comparador de Pastas - Versão Aprimorada

# Variáveis globais para rastreamento
$global:totalFiles = 0
$global:processedItems = 0
$global:folder1Files = @()  # Antes era $global:networkFiles
$global:folder2Files = @()  # Antes era $global:localFiles
$global:uniqueFiles = @()
$global:scriptStartTime = $null # Variável global para rastrear o tempo total

# Configuração de processamento paralelo
$global:defaultMaxThreads = [Environment]::ProcessorCount  # Número de threads baseado nos cores do processador

function Enable-LongPaths {
    param([string]$Path)
    
    if (-not $Path.StartsWith("\\?\")) {
        if ($Path.StartsWith("\\")) {
            # Tratamento especial para caminhos UNC (compartilhamentos de rede)
            return "\\?\UNC\" + $Path.Substring(2)
        } else {
            return "\\?\$Path"
        }
    }
    return $Path
}

function Show-AdvancedProgress {
    param (
        [string]$Stage,
        [int]$Current,
        [int]$Total,
        [DateTime]$StartTime = (Get-Date),
        [string]$Status = "",
        [bool]$HasChanges = $true
    )
    
    # Evitar divisão por zero
    if ($Total -eq 0) { $Total = 1 }
    
    # Calcular porcentagem
    $percentage = [math]::Min(100, [math]::Max(0, [math]::Round(($Current / $Total) * 100, 1)))
    
    # Configurar tamanho da barra
    $barSize = 40
    $fillSize = [math]::Round(($percentage / 100) * $barSize)
    
    # Cores dinâmicas baseadas na porcentagem - CORES MELHORADAS
    $colors = @('Blue', 'Cyan', 'Green', 'Yellow', 'DarkCyan')
    $colorIndex = [math]::Floor($percentage / (100 / ($colors.Count - 1)))
    $colorIndex = [math]::Min($colorIndex, $colors.Count - 1)
    $barColor = $colors[$colorIndex]
    
    # Criar barras de progresso 
    $fill = "█" * $fillSize
    $empty = "░" * ($barSize - $fillSize)
    
    # Calcular tempo estimado restante
    $elapsedTime = [DateTime]::Now - $StartTime
    $itemsPerSecond = if ($elapsedTime.TotalSeconds -gt 0) { $Current / $elapsedTime.TotalSeconds } else { 0 }
    $remainingItems = $Total - $Current
    $remainingSeconds = if ($itemsPerSecond -gt 0) { $remainingItems / $itemsPerSecond } else { 0 }
    $timeLeft = if ($remainingSeconds -gt 0) {
        if ($remainingSeconds -gt 3600) {
            "{0:h\h\ m\m\ s\s}" -f [TimeSpan]::FromSeconds($remainingSeconds)
        } else {
            "{0:m\m\ s\s}" -f [TimeSpan]::FromSeconds($remainingSeconds)
        }
    } else {
        "Concluindo..."
    }
    
    # Velocidade de processamento
    $processingSpeed = if ($elapsedTime.TotalSeconds -gt 0) {
        $itemsPerSecond = $Current / $elapsedTime.TotalSeconds
        if ($itemsPerSecond -gt 1) {
            "{0:N1} itens/seg" -f $itemsPerSecond
        } else {
            "{0:N2} itens/seg" -f $itemsPerSecond
        }
    } else {
        "Calculando..."
    }
    
    if ($HasChanges) {
        # Limpar linha anterior
        Write-Host "`r" -NoNewline
        
        # Estágio atual
        Write-Host "╭─ " -NoNewline -ForegroundColor Cyan
        Write-Host "$Stage " -NoNewline -ForegroundColor White
        Write-Host "─╮" -ForegroundColor Cyan
        
        # Barra de progresso
        Write-Host "│ " -NoNewline -ForegroundColor Cyan
        Write-Host "[$fill" -NoNewline -ForegroundColor $barColor
        Write-Host "$empty] " -NoNewline -ForegroundColor DarkGray
        Write-Host "$percentage%" -NoNewline -ForegroundColor Yellow
        
        # Segunda linha: Contadores e tempo estimado
        Write-Host "`n├─ " -NoNewline -ForegroundColor Cyan
        Write-Host "$Current de $Total" -NoNewline -ForegroundColor White
        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        Write-Host "$processingSpeed" -NoNewline -ForegroundColor Cyan
        
        # Status adicional se fornecido
        if ($Status -ne "") {
            Write-Host "`n├─ " -NoNewline -ForegroundColor Cyan
            Write-Host "$Status" -NoNewline -ForegroundColor Yellow
        }
        
        # Tempo restante
        Write-Host "`n╰─ " -NoNewline -ForegroundColor Cyan
        Write-Host "Restante: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$timeLeft" -NoNewline -ForegroundColor Yellow
        Write-Host "                        " -NoNewline # Espaço para limpar caracteres extras
        
        # Avançar linhas para a próxima atualização
        if ($Status -ne "") {
            Write-Host "`n`n" -NoNewline
        } else {
            Write-Host "`n" -NoNewline
        }
    }
}

function Scan-DirectoriesParallel {
    param(
        [string]$BasePath,
        [int]$MaxThreads = 4,
        [string]$Stage = "Processando",
        [string]$FolderLabel = "Pasta" # Identificar Pasta 1 ou Pasta 2
    )
    
    $startTime = [DateTime]::Now
    Write-Host "`n[ESCANEAMENTO PARALELO]" -ForegroundColor Cyan
    Write-Host "├─ Caminho: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$BasePath" -ForegroundColor White
    Write-Host "├─ Modo: " -NoNewline -ForegroundColor DarkGray
    Write-Host "Processamento Paralelo" -ForegroundColor Green
    Write-Host "└─ Threads: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$MaxThreads" -ForegroundColor Magenta
    
    try {
        # Inicialmente, obter todos os arquivos na raiz
        $rootFiles = @(Get-ChildItem -Path $BasePath -File -ErrorAction SilentlyContinue)
        
        # Obter lista de diretórios de primeiro nível
        $topDirs = @(Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue)
        
        # Criar lista para armazenar todos os arquivos
        $allFiles = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        
        # Adicionar arquivos da raiz à lista
        foreach ($file in $rootFiles) {
            $allFiles.Add($file)
        }
        
        # Preparar diretórios para processamento
        $totalDirs = $topDirs.Count
        $processedDirs = 0
        
        # Usar RunspacePool para processamento paralelo
        $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
        $pool.ApartmentState = "MTA"
        $pool.Open()
        
        # Lista para armazenar todos os jobs
        $jobs = @()
        
        # Função script para processar cada diretório em paralelo
        $scriptBlock = {
            param($directory)
            
            # Obter todos os arquivos recursivamente neste diretório
            try {
                return @(Get-ChildItem -Path $directory.FullName -Recurse -File -ErrorAction SilentlyContinue)
            }
            catch {
                Write-Error "Erro ao processar $($directory.FullName): $($_.Exception.Message)"
                return @()
            }
        }
        
        # Criar e iniciar jobs para cada diretório
        foreach ($dir in $topDirs) {
            $job = [PowerShell]::Create().AddScript($scriptBlock).AddArgument($dir)
            $job.RunspacePool = $pool
            
            $jobs += [PSCustomObject]@{
                Directory = $dir
                PowerShell = $job
                Result = $job.BeginInvoke()
            }
        }
        
        # Processar e coletar resultados
        foreach ($job in $jobs) {
            try {
                $processedDirs++
                
                # Mostrar progresso
                $status = "Escaneando: $($job.Directory.Name)"
                Show-AdvancedProgress -Stage "$FolderLabel - $Stage" -Current $processedDirs -Total $totalDirs -StartTime $startTime -Status $status
                
                # Obter resultado deste job
                $dirFiles = $job.PowerShell.EndInvoke($job.Result)
                
                # Adicionar arquivos à lista global
                foreach ($file in $dirFiles) {
                    $allFiles.Add($file)
                }
                
                # Atualizar status com contagem atual
                $status = "Encontrados: $($allFiles.Count) arquivos até agora"
                Show-AdvancedProgress -Stage "$FolderLabel - $Stage" -Current $processedDirs -Total $totalDirs -StartTime $startTime -Status $status
            }
            catch {
                Write-Host "Erro ao finalizar job para $($job.Directory.FullName): $($_.Exception.Message)" -ForegroundColor Red
            }
            finally {
                # Limpar recursos
                $job.PowerShell.Dispose()
            }
        }
        
        # Fechar o pool
        $pool.Close()
        $pool.Dispose()
        
        # Atualização final
        Show-AdvancedProgress -Stage "$FolderLabel - $Stage" -Current $totalDirs -Total $totalDirs -StartTime $startTime -Status "Total: $($allFiles.Count) arquivos"
        
        Write-Host "`n[RESULTADO DO ESCANEAMENTO PARALELO]" -ForegroundColor Green
        Write-Host "├─ Diretórios processados: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$totalDirs" -ForegroundColor White
        Write-Host "└─ Arquivos encontrados: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($allFiles.Count)" -ForegroundColor White
        
        # Converter ConcurrentBag para array normal
        return $allFiles.ToArray()
    }
    catch {
        Write-Host "Erro ao escanear diretório: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Scan-DirectoriesISE {
    param(
        [string]$BasePath,
        [string]$Stage = "Processando",
        [string]$FolderLabel = "Pasta"  # Novo parâmetro para identificar Pasta 1 ou Pasta 2
    )
    
    $startTime = [DateTime]::Now
    Write-Host "`n[ESCANEAMENTO]" -ForegroundColor Cyan
    Write-Host "├─ Caminho: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$BasePath" -ForegroundColor White
    Write-Host "└─ Modo: " -NoNewline -ForegroundColor DarkGray
    Write-Host "PowerShell ISE (sequencial)" -ForegroundColor Yellow
    
    # Processo sequencial otimizado para PowerShell ISE
    try {
        $allFiles = @()
        
        # Obter arquivos da raiz primeiro
        $rootFiles = Get-ChildItem -Path $BasePath -File -ErrorAction SilentlyContinue
        $allFiles += $rootFiles
        
        # Obter lista de diretórios de primeiro nível
        $topDirs = @(Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue)
        $totalDirs = $topDirs.Count
        $processedDirs = 0
        
        foreach ($dir in $topDirs) {
            $processedDirs++
            
            try {
                # Mostrar diretório atual
                $status = "Escaneando: $($dir.Name)"
                Show-AdvancedProgress -Stage "$FolderLabel - $Stage" -Current $processedDirs -Total $totalDirs -StartTime $startTime -Status $status
                
                # Obter arquivos deste diretório
                $dirFiles = Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue
                $allFiles += $dirFiles
                
                # Atualizar progresso com contagem
                $status = "Encontrados: $($allFiles.Count) arquivos até agora"
                Show-AdvancedProgress -Stage "$FolderLabel - $Stage" -Current $processedDirs -Total $totalDirs -StartTime $startTime -Status $status
            }
            catch {
                Write-Host "Erro ao processar $($dir.FullName): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # Atualização final
        Show-AdvancedProgress -Stage "$FolderLabel - $Stage" -Current $totalDirs -Total $totalDirs -StartTime $startTime -Status "Total: $($allFiles.Count) arquivos"
        
        Write-Host "`n[RESULTADO DO ESCANEAMENTO]" -ForegroundColor Green
        Write-Host "├─ Diretórios processados: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$totalDirs" -ForegroundColor White
        Write-Host "└─ Arquivos encontrados: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($allFiles.Count)" -ForegroundColor White
        
        return $allFiles
    }
    catch {
        Write-Host "Erro ao escanear diretório: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Format-FileSize {
    param([double]$SizeInBytes)
    
    if ($SizeInBytes -ge 1GB) {
        return "{0:N2} GB" -f ($SizeInBytes / 1GB)
    } elseif ($SizeInBytes -ge 1MB) {
        return "{0:N2} MB" -f ($SizeInBytes / 1MB)
    } elseif ($SizeInBytes -ge 1KB) {
        return "{0:N2} KB" -f ($SizeInBytes / 1KB)
    } else {
        return "{0:N0} bytes" -f $SizeInBytes
    }
}

function Ensure-TempFolder {
    param([string]$Path)
    
    if (-not (Test-Path -Path $Path)) {
        try {
            Write-Host "`n[CRIANDO DIRETÓRIO]" -ForegroundColor Yellow
            Write-Host "Criando pasta $Path..." -NoNewline
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Host " ✓" -ForegroundColor Green
        }
        catch {
            Write-Host "`n[ERRO]" -ForegroundColor Red
            Write-Host "Não foi possível criar a pasta $Path`: $($_.Exception.Message)" -ForegroundColor Red
            exit
        }
    }
}

function Format-Path {
    param(
        [string]$Path,
        [int]$MaxLength = 100
    )
    
    if ($Path.Length -le $MaxLength) {
        return $Path
    }
    
    $start = $Path.Substring(0, [math]::Floor($MaxLength/2) - 3)
    $end = $Path.Substring($Path.Length - [math]::Floor($MaxLength/2))
    return "${start}...${end}"
}

function Generate-FileName {
    param(
        [string]$Folder1Path,
        [string]$Folder2Path,
        [string]$Extension,  # Exemplo: ".html"
        [string]$BasePath = "C:\temp"  # Pasta base padrão para salvar relatórios
    )
    
    # Extrai o nome da pasta final do caminho completo
    function Get-FolderName {
        param([string]$Path)
        
        # Remover a barra final se existir
        $Path = $Path.TrimEnd('\').TrimEnd('/')
        
        # Obter o nome da última pasta no caminho
        $folderName = Split-Path -Path $Path -Leaf
        
        # Se o resultado for vazio (ex: para "C:\"), use o drive
        if ([string]::IsNullOrEmpty($folderName)) {
            $folderName = $Path.Replace(":", "")
        }
        
        # Limpar caracteres inválidos para nome de arquivo
        $invalidChars = [IO.Path]::GetInvalidFileNameChars()
        foreach ($char in $invalidChars) {
            $folderName = $folderName.Replace($char, '_')
        }
        
        return $folderName
    }
    
    # Obter os nomes das pastas
    $folder1Name = Get-FolderName -Path $Folder1Path
    $folder2Name = Get-FolderName -Path $Folder2Path
    
    # Adicionar timestamp para evitar sobrescrever arquivos anteriores
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    # Criar o nome do arquivo
    $fileName = "Comparacao_{0}_vs_{1}_{2}{3}" -f $folder1Name, $folder2Name, $timestamp, $Extension
    
    # Garantir que o diretório de destino existe
    if (-not (Test-Path -Path $BasePath)) {
        New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
    }
    
    # Retornar o caminho completo
    return Join-Path -Path $BasePath -ChildPath $fileName
}

function Export-HTMLReport {
    param(
        [array]$UniqueFiles,
        [string]$Folder1Path,
        [string]$Folder2Path,
        [string]$OutputHTMLFile,
        [int]$Folder1Count,
        [int]$Folder2Count,
        [DateTime]$StartTime,
        [TimeSpan]$ExecutionTime, # Parâmetro para receber o tempo já calculado
        [switch]$ShowDebug = $false
    )
    
    # CORREÇÃO: Usar o tempo de execução passado como parâmetro em vez de recalcular
    # Se ExecutionTime for fornecido, use-o; caso contrário, calcule com base na hora de início
    $totalTime = if ($ExecutionTime) { 
        $ExecutionTime 
    } else { 
        [DateTime]::Now - $StartTime 
    }

    # Garantir que tempos pequenos sejam exibidos corretamente
    $hours = [Math]::Floor($totalTime.TotalHours)
    $minutes = $totalTime.Minutes
    $seconds = $totalTime.Seconds

    # Arredondar para cima caso seja menor que 1 segundo
    if (($totalTime.TotalSeconds -gt 0) -and ($seconds -eq 0)) {
        $seconds = 1
    }

    # CORREÇÃO: Formatar explicitamente para garantir que os zeros sejam exibidos
    $formattedTime = "{0}h {1:D2}m {2:D2}s" -f $hours, $minutes, $seconds
    
    # Analisar os dados para gráficos
    $totalFiles = $UniqueFiles.Count
    $totalSize = 0
    $extensionData = @{}
    
    # CORREÇÃO: Usar OrderedDictionary para garantir a ordem correta das categorias
    $sizeRanges = [ordered]@{
        "Arquivos 0B a 10KB" = 0
        "Arquivos 10KB a 100KB" = 0
        "Arquivos 100KB a 10MB" = 0
        "Arquivos 10MB a 1GB" = 0
        "Arquivos Acima de 1GB" = 0
    }
    
    # Estrutura para rastrear todos os níveis de diretório
    $dirCounts = @{}
    
    # Mostrar apenas a mensagem inicial, sem detalhes
    Write-Host "`n[INICIANDO ANÁLISE DE DADOS]" -ForegroundColor Yellow
    Write-Host "Total de arquivos para análise: $totalFiles" -ForegroundColor Yellow
    
    foreach ($file in $UniqueFiles) {
        # Extrair tamanho do arquivo
        $fileSize = 0
        $sizeStr = $file.Tamanho
        
        # CORREÇÃO: Melhorar a extração do tamanho para lidar com separadores decimais locais e garantir precisão
        # Remover espaços e caracteres não numéricos antes de converter
        if ($sizeStr -match "([\d\.\,]+)\s*GB") {
            # Substituir vírgula por ponto para garantir consistência na conversão
            $sizeValue = ($Matches[1] -replace '\.' -replace ',', '.').Trim()
            try {
                $fileSize = [double]$sizeValue * 1GB
            } catch {
                $fileSize = 2GB # Valor padrão alto em caso de erro
            }
        } elseif ($sizeStr -match "([\d\.\,]+)\s*MB") {
            $sizeValue = ($Matches[1] -replace '\.' -replace ',', '.').Trim()
            try {
                $fileSize = [double]$sizeValue * 1MB
            } catch {
                $fileSize = 0
            }
        } elseif ($sizeStr -match "([\d\.\,]+)\s*KB") {
            $sizeValue = ($Matches[1] -replace '\.' -replace ',', '.').Trim()
            try {
                $fileSize = [double]$sizeValue * 1KB
            } catch {
                $fileSize = 0
            }
        } else {
            # Tenta extrair um número puro caso não tenha unidade
            if ($sizeStr -match "([\d\.\,]+)") {
                $sizeValue = ($Matches[1] -replace '\.' -replace ',', '.').Trim()
                try {
                    $fileSize = [double]$sizeValue
                } catch {
                    $fileSize = 0
                }
            } else { 
                $fileSize = 0 
            }
        }
        
        $totalSize += $fileSize
        
        # CORREÇÃO: Categorização por tamanho com garantia de que arquivos grandes sejam contabilizados
        if ($fileSize -lt 10 * 1KB) {
            $sizeRanges["Arquivos 0B a 10KB"]++
        }
        elseif ($fileSize -ge 10 * 1KB -and $fileSize -lt 100 * 1KB) {
            $sizeRanges["Arquivos 10KB a 100KB"]++
        }
        elseif ($fileSize -ge 100 * 1KB -and $fileSize -lt 10 * 1MB) {
            $sizeRanges["Arquivos 100KB a 10MB"]++
        }
        elseif ($fileSize -ge 10 * 1MB -and $fileSize -lt 1 * 1GB) {
            $sizeRanges["Arquivos 10MB a 1GB"]++
        }
        else {
            # CORREÇÃO: Garantir que qualquer arquivo maior ou igual a 1GB seja contabilizado
            $sizeRanges["Arquivos Acima de 1GB"]++
        }
        
        # Contar por extensão
        try {
            $fileName = $file.'Nome do Arquivo'
            $ext = [System.IO.Path]::GetExtension($fileName).ToLower()
            
            # Se a extensão for vazia, use um rótulo especial
            if ([string]::IsNullOrEmpty($ext)) { 
                $ext = "[sem extensão]" 
            }
            
            # Incrementar contador de extensão
            if ($extensionData.ContainsKey($ext)) {
                $extensionData[$ext]++
            } else {
                $extensionData[$ext] = 1
            }
            
        } catch {
            # Incrementar contador para arquivos com erro
            if (-not $extensionData.ContainsKey("[erro]")) {
                $extensionData["[erro]"] = 0
            }
            $extensionData["[erro]"]++
        }
        
        # Contar por diretório - VERSÃO SIMPLIFICADA PARA MOSTRAR APENAS SUBPASTAS
        try {
            if (-not [string]::IsNullOrEmpty($file.'Caminho Completo') -and -not [string]::IsNullOrEmpty($Folder1Path)) {
                $fullPath = $file.'Caminho Completo'
                
                # Verificar se o caminho da pasta 1 é um prefixo do caminho completo
                if ($fullPath.StartsWith($Folder1Path)) {
                    $relPath = $fullPath.Substring($Folder1Path.Length).TrimStart('\')
                    $parts = $relPath.Split('\')
                    
                    # Pegar apenas o primeiro nível de pasta (subpasta)
                    if ($parts.Length -gt 0 -and -not [string]::IsNullOrEmpty($parts[0])) {
                        $subDir = $parts[0]
                        
                        # Incrementar contador de diretório
                        if ($dirCounts.ContainsKey($subDir)) {
                            $dirCounts[$subDir]++
                        } else {
                            $dirCounts[$subDir] = 1
                        }
                    } else {
                        # Se o arquivo estiver na raiz
                        if (-not $dirCounts.ContainsKey("(Raiz)")) {
                            $dirCounts["(Raiz)"] = 0
                        }
                        $dirCounts["(Raiz)"]++
                    }
                } else {
                    # Caminho não está na rede
                    if (-not $dirCounts.ContainsKey("(Outro)")) {
                        $dirCounts["(Outro)"] = 0
                    }
                    $dirCounts["(Outro)"]++
                }
            } else {
                # Se o caminho estiver vazio
                if (-not $dirCounts.ContainsKey("(Desconhecido)")) {
                    $dirCounts["(Desconhecido)"] = 0
                }
                $dirCounts["(Desconhecido)"]++
            }
        } catch {
            # Incrementar contador para diretórios com erro
            if (-not $dirCounts.ContainsKey("(Erro)")) {
                $dirCounts["(Erro)"] = 0
            }
            $dirCounts["(Erro)"]++
        }
    }
    
    # Criar arrays de objetos simples para os gráficos (mais fácil de serializar)
    $extensionChartArray = @()
    $sizeRangesChartArray = @()
    $dirChartArray = @()
    
    # Preparar dados de extensão para o gráfico
    if ($extensionData.Count -gt 0) {
        $extensionData.GetEnumerator() | 
            Sort-Object -Property Value -Descending | 
            Select-Object -First 10 | 
            ForEach-Object {
                $extensionChartArray += @{
                    label = $_.Key
                    value = [int]$_.Value
                }
            }
    }
    
    # Se não houver dados de extensão, usar dados fictícios
    if ($extensionChartArray.Count -eq 0) {
        $extensionChartArray = @(
            @{ label = ".txt"; value = 10 },
            @{ label = ".pdf"; value = 5 },
            @{ label = ".doc"; value = 3 }
        )
    }
    
    # CORREÇÃO: Usar a ordem explícita das categorias de tamanho para o gráfico
    foreach ($category in $sizeRanges.Keys) {
        $sizeRangesChartArray += @{
            label = $category
            value = [int]$sizeRanges[$category]
        }
    }
    
    # Preparar dados de diretório para o gráfico com formato simplificado
    # CORREÇÃO: Alterado de 10 para 5 diretórios
    if ($dirCounts.Count -gt 0) {
        $dirCounts.GetEnumerator() | 
            Sort-Object -Property Value -Descending | 
            Select-Object -First 5 | 
            ForEach-Object {
                $subpasta = $_.Key
                $arquivos = [int]$_.Value
                
                # Remover a extensão HTML se presente
                if ($subpasta -match '(.*)\.html$') {
                    $subpasta = $Matches[1]
                }
                
                # Limitar o tamanho do nome para não ficar muito grande no gráfico
                if ($subpasta.Length -gt 30) {
                    $subpasta = $subpasta.Substring(0, 27) + "..."
                }
                
                # Formato personalizado para rótulos do gráfico de diretório
                # Nome da subpasta seguido pelo número de arquivos
                $labelText = "$subpasta ($arquivos arquivos)"
                
                $dirChartArray += @{
                    label = $labelText
                    value = $arquivos
                }
            }
    }
    
    # Se não houver dados de diretório, usar dados fictícios
    if ($dirChartArray.Count -eq 0) {
        $dirChartArray = @(
            @{ label = "Documentos (10 arquivos)"; value = 10 },
            @{ label = "Imagens (5 arquivos)"; value = 5 },
            @{ label = "Outros (3 arquivos)"; value = 3 }
        )
    }
    
    # Converter para JSON (sem exibir mensagem no console)
    $extensionChartJson = $extensionChartArray | ConvertTo-Json -Compress
    $sizeRangesChartJson = $sizeRangesChartArray | ConvertTo-Json -Compress
    $dirChartJson = $dirChartArray | ConvertTo-Json -Compress
    
    # Substituir aspas duplas por aspas simples escapadas
    $extensionChartJson = $extensionChartJson.Replace('"', "'")
    $sizeRangesChartJson = $sizeRangesChartJson.Replace('"', "'")
    $dirChartJson = $dirChartJson.Replace('"', "'")
    
    # CORREÇÃO: Garantir o formato correto para o tamanho total
    # Formato de tamanho legível
    $formattedTotalSize = if ($totalSize -ge 1TB) {
        "{0:N2} TB" -f ($totalSize / 1TB)
    } elseif ($totalSize -ge 1GB) {
        "{0:N2} GB" -f ($totalSize / 1GB)
    } elseif ($totalSize -ge 1MB) {
        "{0:N2} MB" -f ($totalSize / 1MB)
    } else {
        "{0:N2} KB" -f ($totalSize / 1KB)
    }
    
    # Formatar totais com separador de milhar
    $formattedFolder1Count = '{0:N0}' -f $Folder1Count
    $formattedFolder2Count = '{0:N0}' -f $Folder2Count
    $formattedTotalAnalyzed = '{0:N0}' -f ($Folder1Count + $Folder2Count)
    $formattedUniqueFiles = '{0:N0}' -f $UniqueFiles.Count
    
    # Formatar data/hora atual
    $reportDate = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    
    # Extrair os nomes das pastas para o título
    $folder1Name = Split-Path -Path $Folder1Path -Leaf
    $folder2Name = Split-Path -Path $Folder2Path -Leaf
    
    # Se for um drive, extrair apenas a letra
    if ([string]::IsNullOrEmpty($folder1Name)) {
        $folder1Name = $Folder1Path.Replace(":", "")
    }
    
    if ([string]::IsNullOrEmpty($folder2Name)) {
        $folder2Name = $Folder2Path.Replace(":", "")
    }
    
    # Dados da tabela - CORREÇÃO: Remover limite de 1000 itens
    $tableRows = ""
    $count = 0
    
    foreach ($file in $UniqueFiles) {
        $count++
        
        # CORREÇÃO: Exibir todos os arquivos sem limite
        $relativePath = $file.'Caminho Completo'.Substring($Folder1Path.Length).TrimStart('\')
        $fullPath = $file.'Caminho Completo'
        $rowClass = if ($count % 2 -eq 0) { "row-even" } else { "row-odd" }
        $tableRows += @"
        <tr class="$rowClass" id="row-$count">
            <td class="p-3 border-b border-gray-600 text-center">
                <input type="checkbox" id="check-$count" class="file-check w-5 h-5 cursor-pointer" 
                       onchange="toggleRowDone(this, 'row-$count')" />
            </td>
            <td class="p-3 border-b border-gray-600">$count</td>
            <td class="p-3 border-b border-gray-600 font-medium">
                $($file.'Nome do Arquivo')
                <button class="copy-cell-btn" onclick="copyToClipboard('fullPath$count')" title="Copiar caminho completo">
                    <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                        <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
                    </svg>
                </button>
                <span id="fullPath$count" style="display:none">$fullPath</span>
            </td>
            <td class="p-3 border-b border-gray-600">
                $fullPath
                <button class="copy-cell-btn" onclick="copyToClipboard('fullPath2$count')" title="Copiar caminho completo">
                    <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                        <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
                    </svg>
                </button>
                <span id="fullPath2$count" style="display:none">$fullPath</span>
            </td>
            <td class="p-3 border-b border-gray-600 text-right">$($file.Tamanho)</td>
        </tr>
"@
    }
    
    # CORREÇÃO: Melhorar a inicialização do DataTables com opções de paginação e desempenho
    # NOVA CORREÇÃO: Corrigido problema com paginação - Alterado initComplete e adicionado callback para eventos de paginação
    $dataTablesInitCode = @'
            // Função para converter tamanho formatado em bytes para ordenação correta
            function convertSizeToBytes(sizeStr) {
                // Se não for uma string, retorna 0
                if (!sizeStr || typeof sizeStr !== 'string') return 0;
                
                // Extrair o valor numérico e a unidade
                const regex = /([\d\.,]+)\s*(bytes|KB|MB|GB|TB)/i;
                const match = sizeStr.match(regex);
                
                if (!match) return 0;
                
                // Obter valor numérico (substituindo vírgula por ponto para cálculos)
                let size = parseFloat(match[1].replace(',', '.'));
                const unit = match[2].toUpperCase();
                
                // Converter para bytes baseado na unidade
                switch (unit) {
                    case 'TB': 
                        return size * 1024 * 1024 * 1024 * 1024;
                    case 'GB': 
                        return size * 1024 * 1024 * 1024;
                    case 'MB': 
                        return size * 1024 * 1024;
                    case 'KB': 
                        return size * 1024;
                    default: 
                        return size;
                }
            }

            // Registrar plugin de ordenação para tamanhos de arquivo
            $.fn.dataTable.ext.type.order['file-size-pre'] = function(data) {
                return convertSizeToBytes(data);
            };

            // CORREÇÃO: Adiciona fixação de paginação com novo delegate
            $(document).on('click', '.paginate_button, .paginate_button.current', function(e) {
                console.log("Clique em botão de paginação detectado");
                setTimeout(function() {
                    restoreCheckboxState();
                    updateProgressDisplay();
                }, 300);
            });

            // Inicializar DataTable com configurações otimizadas para grandes tabelas
            $(document).ready(function() {
                var tableOptions = {
                    language: {
                        url: '//cdn.datatables.net/plug-ins/1.10.21/i18n/Portuguese-Brasil.json'
                    },
                    pageLength: 50,
                    lengthMenu: [10, 25, 50, 100, 250, 500, 1000],
                    deferRender: true,
                    processing: true,
                    paging: true,
                    autoWidth: false,  // IMPORTANTE: Manter falso para evitar recálculo de largura
                    stateSave: true,
                    dom: 'lfrtip',
                    pagingType: 'full_numbers',  // CORREÇÃO: Use paginação completa com todos os controles
                    scrollCollapse: false,
                    // CORREÇÃO: Adicionar configurações para estabilidade de layout
                    scrollX: true,     // Permitir rolagem horizontal
                    fixedHeader: true, // Manter cabeçalho fixo
                    responsive: false, // Desativar responsividade que pode causar problemas
                    columnDefs: [
                        // Desativar ordenação na coluna de checkboxes (primeira coluna - índice 0)
                        { orderable: false, targets: 0, width: "50px" },
                        // Aplicar ordenação personalizada para coluna de tamanho (última coluna - índice 4)
                        { type: 'file-size', targets: 4, width: "120px" },
                        // Definir larguras explícitas para outras colunas
                        { width: "50px", targets: 1 },  // Coluna #
                        { width: "25%", targets: 2 },   // Nome do Arquivo
                        { width: "auto", targets: 3 }   // Caminho Completo
                    ],
                    createdRow: function(row, data, index) {
                        $(row).addClass(index % 2 === 0 ? 'row-odd' : 'row-even');
                    },
                    initComplete: function() {
                        console.log('DataTable inicializada com sucesso');
                        // CORREÇÃO: Adicionar delegação de eventos para garantir que os botões de paginação funcionem
                        $('.dataTables_paginate').on('click', '.paginate_button', function() {
                            console.log('Botão de paginação clicado');
                            setTimeout(function() {
                                restoreCheckboxState();
                                updateProgressDisplay();
                            }, 300);
                        });
                        
                        // Atualizar progresso após inicialização
                        setTimeout(function() {
                            restoreCheckboxState();
                            updateProgressDisplay();
                            
                            // CORREÇÃO: Verificação periódica do estado do progresso
                            setInterval(verifyProgressState, 5000);
                        }, 500);
                    },
                    drawCallback: function() {
                        // Restaurar estado dos checkboxes após mudança de página
                        setTimeout(function() {
                            restoreCheckboxState();
                            updateProgressDisplay();
                            
                            // CORREÇÃO: Forçar recálculo de larguras de colunas
                            this.api().columns.adjust();
                            
                            // CORREÇÃO: Garantir que delegação de eventos esteja funcionando
                            $('.paginate_button').off('click').on('click', function(e) {
                                console.log('Clique em botão de paginação (drawCallback)');
                                setTimeout(function() {
                                    restoreCheckboxState();
                                    updateProgressDisplay();
                                }, 300);
                            });
                        }, 200);
                    }
                };
                
                // Inicializar a tabela
                var table = $('#filesTable').DataTable(tableOptions);
                
                // CORREÇÃO: Adicionar listener para quando o número de entradas mudar
                $('#filesTable').on('length.dt', function() {
                    setTimeout(function() {
                        table.columns.adjust().draw();
                    }, 300);
                });
                
                // CORREÇÃO: Verificar se os controles foram renderizados corretamente
                if ($('.dataTables_length').length === 0 || $('.dataTables_filter').length === 0) {
                    console.error('Controles do DataTable não foram renderizados corretamente');
                    // Forçar re-renderização
                    table.destroy();
                    $('#filesTable').DataTable(tableOptions);
                }
                
                // CORREÇÃO: Garantir que o estado inicial seja carregado
                setTimeout(function() {
                    updateProgressDisplay();
                }, 1000);
                
                // CORREÇÃO: Adicionar manipulador de eventos global para checkboxes
                $(document).on('change', '.file-check', function() {
                    const checkbox = this;
                    const rowId = checkbox.id.replace('check-', 'row-');
                    toggleRowDone(checkbox, rowId);
                });
                
                // CORREÇÃO: Garantir que a paginação funcione mesmo após AJAX
                $(document).off('click', '.paginate_button').on('click', '.paginate_button', function(e) {
                    console.log('Evento de paginação delegado global');
                    setTimeout(function() {
                        restoreCheckboxState();
                        updateProgressDisplay();
                    }, 300);
                });
            });
'@

    # CORREÇÃO: Código para atualizar o progresso contando todos os checkboxes, 
    # inclusive os que não estão visíveis na página atual
    $updateProgressCode = @'
        // Função para atualizar a exibição de progresso
        function updateProgressDisplay() {
            // Pegar todos os estados salvos no localStorage
            const savedState = localStorage.getItem('fileChecksState');
            let completedFiles = 0;
            
            if (savedState) {
                try {
                    const state = JSON.parse(savedState);
                    // Contar quantos itens estão marcados como true
                    completedFiles = Object.values(state).filter(value => value === true).length;
                    
                    // Log para debug da contagem
                    console.log(`Contados ${completedFiles} arquivos concluídos de ${Object.keys(state).length} total`);
                } catch (e) {
                    console.error('Erro ao analisar o estado salvo:', e);
                    // Reset em caso de erro
                    localStorage.removeItem('fileChecksState');
                }
            }
            
            // CORREÇÃO: Obter o número total real de arquivos
            const totalFilesCount = parseInt(document.getElementById('totalFiles').textContent.replace(/\D/g, ''));
            
            // Calcular o percentual
            const percentage = totalFilesCount > 0 ? Math.round((completedFiles / totalFilesCount) * 100) : 0;
            
            // Atualizar os elementos visuais
            const progressBar = document.getElementById('progressBar');
            const percentageDisplay = document.getElementById('progressPercentage');
            const pendingFilesDisplay = document.getElementById('pendingFiles');
            const completedFilesDisplay = document.getElementById('completedFiles');
            
            // Atualizar a barra de progresso
            if (progressBar) progressBar.style.width = `${percentage}%`;
            
            // Adicionar ou remover a classe de animação de pulso
            if (progressBar) {
                if (percentage > 0 && percentage < 100) {
                    progressBar.classList.add('pulse');
                } else {
                    progressBar.classList.remove('pulse');
                }
            }
            
            // CORREÇÃO: Atualizar os contadores com o número real
            if (percentageDisplay) percentageDisplay.textContent = `${percentage}%`;
            if (pendingFilesDisplay) pendingFilesDisplay.textContent = totalFilesCount - completedFiles;
            if (completedFilesDisplay) completedFilesDisplay.textContent = completedFiles;
            
            console.log(`Progresso atualizado: ${completedFiles}/${totalFilesCount} (${percentage}%)`);
        }
'@

    # CORREÇÃO: Melhorar a restauração dos checkboxes para funcionar com paginação
    $restoreCheckboxState = @'
        // Restaurar estado dos checkboxes
        function restoreCheckboxState() {
            const savedState = localStorage.getItem('fileChecksState');
            
            if (savedState) {
                try {
                    const state = JSON.parse(savedState);
                    
                    // Aplicar apenas aos checkboxes visíveis na página atual
                    const visibleCheckboxes = document.querySelectorAll('.file-check');
                    
                    visibleCheckboxes.forEach(checkbox => {
                        if (state[checkbox.id] !== undefined) {
                            checkbox.checked = state[checkbox.id];
                            if (state[checkbox.id]) {
                                const rowId = checkbox.id.replace('check-', 'row-');
                                const row = document.getElementById(rowId);
                                if (row) row.classList.add('file-done');
                            }
                        }
                    });
                    
                    console.log(`Restaurado estado de ${visibleCheckboxes.length} checkboxes visíveis`);
                    
                    // Log para debug do estado restaurado
                    const checkedCount = Object.values(state).filter(value => value === true).length;
                    console.log(`Restaurado dados: total de ${Object.keys(state).length} itens no estado, ${checkedCount} marcados como concluídos`);
                } catch (e) {
                    console.error('Erro ao restaurar estado dos checkboxes:', e);
                    // Reset em caso de erro
                    localStorage.removeItem('fileChecksState');
                }
            }
        }
'@

    # CORREÇÃO: Código para salvar o estado dos checkboxes
    $saveCheckboxState = @'
        // Salvar estado de todos os checkboxes
        function saveCheckboxState() {
            try {
                // Primeiro, pegar qualquer estado salvo anteriormente
                let savedState = {};
                const savedStateStr = localStorage.getItem('fileChecksState');
                
                if (savedStateStr) {
                    savedState = JSON.parse(savedStateStr);
                }
                
                // Atualizar apenas os checkboxes visíveis
                const visibleCheckboxes = document.querySelectorAll('.file-check');
                
                visibleCheckboxes.forEach(checkbox => {
                    savedState[checkbox.id] = checkbox.checked;
                });
                
                localStorage.setItem('fileChecksState', JSON.stringify(savedState));
                console.log(`Salvo estado de ${visibleCheckboxes.length} checkboxes visíveis`);
                
                // Log para debug do estado salvo
                const checkedCount = Object.values(savedState).filter(value => value === true).length;
                console.log(`Total de ${Object.keys(savedState).length} itens no estado, ${checkedCount} marcados como concluídos`);
            } catch (e) {
                console.error('Erro ao salvar estado dos checkboxes:', e);
            }
        }
'@

    # CORREÇÃO: Função para verificar estado do progresso
    $verifyProgressState = @'
        // Verificar estado do progresso periodicamente
        function verifyProgressState() {
            // Verificar dados salvos
            const savedState = localStorage.getItem('fileChecksState');
            if (savedState) {
                try {
                    const state = JSON.parse(savedState);
                    const checkedCount = Object.values(state).filter(value => value === true).length;
                    const totalCount = Object.keys(state).length;
                    
                    console.log(`VERIFICAÇÃO: ${checkedCount} itens marcados como concluídos de ${totalCount} total`);
                    
                    // Atualizar exibição de progresso
                    const completedFilesDisplay = document.getElementById('completedFiles');
                    if (completedFilesDisplay) {
                        const currentDisplayed = parseInt(completedFilesDisplay.textContent);
                        if (currentDisplayed !== checkedCount) {
                            console.warn(`Inconsistência detectada: exibindo ${currentDisplayed}, deveria ser ${checkedCount}`);
                            completedFilesDisplay.textContent = checkedCount;
                            
                            // Atualizar outros elementos
                            const totalFilesCount = parseInt(document.getElementById('totalFiles').textContent.replace(/\D/g, ''));
                            const percentage = totalFilesCount > 0 ? Math.round((checkedCount / totalFilesCount) * 100) : 0;
                            
                            const progressBar = document.getElementById('progressBar');
                            const percentageDisplay = document.getElementById('progressPercentage');
                            const pendingFilesDisplay = document.getElementById('pendingFiles');
                            
                            if (progressBar) progressBar.style.width = `${percentage}%`;
                            if (percentageDisplay) percentageDisplay.textContent = `${percentage}%`;
                            if (pendingFilesDisplay) pendingFilesDisplay.textContent = totalFilesCount - checkedCount;
                        }
                    }
                } catch (e) {
                    console.error('Erro na verificação de estado:', e);
                }
            }
        }
'@

    # CORREÇÃO: Função para lidar com o clique nos botões de paginação
    $paginationHandler = @'
        // CORREÇÃO: Adicionar manipulador de eventos especifico para paginação
        function setupPaginationHandlers() {
            console.log("Configurando manipuladores de paginação");
            
            // Usar delegação de eventos para botões de paginação
            $(document).off('click.pagination').on('click.pagination', '.paginate_button', function(e) {
                console.log("Botão de paginação clicado via delegação");
                setTimeout(function() {
                    restoreCheckboxState();
                    updateProgressDisplay();
                }, 300);
            });
            
            // Adicionar manipulador direto à div .dataTables_paginate
            $('.dataTables_paginate').off('click.pagination').on('click.pagination', '.paginate_button', function(e) {
                console.log("Botão de paginação clicado via container");
                setTimeout(function() {
                    restoreCheckboxState();
                    updateProgressDisplay();
                }, 300);
            });
        }
'@

    # CORREÇÃO: Código para gráficos - garantir que todas as categorias do gráfico sejam mostradas
    $chartInitCode = @'
            // Verificar se os elementos canvas existem
            if (!document.getElementById('sizeChart')) {
                console.error('Elemento sizeChart não encontrado!');
            }
            if (!document.getElementById('extensionChart')) {
                console.error('Elemento extensionChart não encontrado!');
            }
            if (!document.getElementById('dirChart')) {
                console.error('Elemento dirChart não encontrado!');
            }
            
            // CORREÇÃO: Detectar e corrigir problemas no gráfico após renderização
            function checkChartVisibility(chartId, expectedLabels) {
                setTimeout(function() {
                    const chartElement = document.getElementById(chartId);
                    if (chartElement && chartElement.__chartjs__ && chartElement.__chartjs__.active === false) {
                        console.warn(`Problema detectado no gráfico ${chartId}, tentando recriar...`);
                        // O gráfico está inativo, tentar recriar
                        const ctx = chartElement.getContext('2d');
                        if (ctx && window.chartConfigs && window.chartConfigs[chartId]) {
                            new Chart(ctx, window.chartConfigs[chartId]);
                        }
                    }
                }, 1000);
            }
            
            // Inicializar objeto global para armazenar configurações de gráficos
            window.chartConfigs = {};
'@

    # CORREÇÃO: Adicionar código para garantir que o gráfico mostre arquivos grandes
    $saveSizeChartData = @'
            // CORREÇÃO PRIORITÁRIA: Garantir que arquivos acima de 1GB apareçam no gráfico
            console.log("Processando dados para o gráfico de tamanho:", sizeData);
            
            // FORÇAR valor mínimo para arquivos grandes (garantindo visibilidade)
            const bigFilesCategory = sizeData.find(item => item.label === "Arquivos Acima de 1GB");
            if (bigFilesCategory) {
                console.log("Valor original para 'Arquivos Acima de 1GB':", bigFilesCategory.value);
                
                // Se houver pelo menos 1 arquivo grande, garantir que seja visível no gráfico
                if (bigFilesCategory.value > 0 && bigFilesCategory.value < 5) {
                    // Para arquivos grandes, uma pequena quantidade ainda é significativa
                    // Forçar um valor mínimo de exibição para garantir visibilidade
                    console.log("Ajustando visualização para tornar arquivos grandes visíveis");
                    
                    // Apenas para visualização - não altera os dados exibidos nos tooltips
                    const minDisplayValue = 10; 
                    
                    // Guardar o valor original para mostrar no tooltip
                    bigFilesCategory.originalValue = bigFilesCategory.value;
                    bigFilesCategory.displayAdjusted = true;
                    
                    // Ajustar o valor para visualização
                    bigFilesCategory.value = minDisplayValue;
                }
            } else {
                console.error("Categoria 'Arquivos Acima de 1GB' não encontrada nos dados!");
            }
            
            // MODIFICAÇÃO: Cores mais vibrantes para facilitar identificação
            const sizeChartColors = [
                '#A86BD2', // Roxo (0B a 10KB)
                '#1E90FF', // Azul (10KB a 100KB)
                '#32CD32', // Verde (100KB a 10MB)
                '#FFA500', // Laranja (10MB a 1GB)
                '#FF0000'  // Vermelho (Acima de 1GB) - mais vibrante
            ];
            
            // MODIFICAÇÃO: Configuração para gráfico de barras horizontais
            window.chartConfigs.sizeChart = {
                type: 'bar',
                data: {
                    labels: sizeData.map(item => item.label),
                    datasets: [{
                        label: 'Quantidade de Arquivos',
                        data: sizeData.map(item => item.value),
                        backgroundColor: sizeChartColors,
                        borderWidth: 1,
                        borderColor: '#111827',
                        hoverOffset: 15
                    }]
                },
                options: {
                    indexAxis: 'y',  // Eixo horizontal para melhor visualização
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: false,
                            position: 'bottom'
                        },
                        tooltip: {
                            backgroundColor: '#1f2937',
                            titleColor: '#93c5fd',
                            bodyColor: '#f3f4f6',
                            borderColor: '#3b82f6',
                            borderWidth: 1,
                            padding: 10,
                            boxPadding: 5,
                            callbacks: {
                                label: function(context) {
                                    const dataItem = sizeData[context.dataIndex];
                                    // Se o valor foi ajustado, mostrar o valor original
                                    let value = dataItem.displayAdjusted ? dataItem.originalValue : context.raw;
                                    const total = sizeData.reduce((a, b) => a + (typeof b === 'object' ? 
                                        (b.displayAdjusted ? b.originalValue : b.value) : 0), 0);
                                    
                                    // Calcular a porcentagem baseada no valor real, não no ajustado
                                    const percentage = Math.round((value / total) * 100);
                                    return `${value} arquivos (${percentage}%)`;
                                }
                            }
                        }
                    },
                    scales: {
                        x: {
                            beginAtZero: true,
                            grid: {
                                color: 'rgba(243, 244, 246, 0.1)'
                            },
                            ticks: {
                                color: '#d1d5db'
                            }
                        },
                        y: {
                            grid: {
                                display: false
                            },
                            ticks: {
                                color: '#d1d5db',
                                font: {
                                    weight: 'bold'
                                }
                            }
                        }
                    }
                }
            };
            
            // Renderizar o gráfico
            const sizeCtx = document.getElementById('sizeChart').getContext('2d');
            new Chart(sizeCtx, window.chartConfigs.sizeChart);
            
            // Verificar se o gráfico está visível após renderização
            checkChartVisibility('sizeChart');
            
            // Gráfico de extensões (barra vertical)
            window.chartConfigs.extensionChart = {
                type: 'bar',
                data: {
                    labels: extensionData.map(item => item.label),
                    datasets: [{
                        label: 'Quantidade',
                        data: extensionData.map(item => item.value),
                        backgroundColor: '#3b82f6',
                        borderWidth: 0
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: false
                        },
                        tooltip: {
                            backgroundColor: '#1f2937',
                            titleColor: '#93c5fd',
                            bodyColor: '#f3f4f6',
                            borderColor: '#3b82f6',
                            borderWidth: 1,
                            padding: 10,
                            boxPadding: 5
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            grid: {
                                color: 'rgba(243, 244, 246, 0.1)'
                            },
                            ticks: {
                                color: '#d1d5db'
                            }
                        },
                        x: {
                            grid: {
                                display: false
                            },
                            ticks: {
                                color: '#d1d5db'
                            }
                        }
                    }
                }
            };
            
            const extCtx = document.getElementById('extensionChart').getContext('2d');
            new Chart(extCtx, window.chartConfigs.extensionChart);
            
            // Gráfico de diretórios (barra horizontal)
            window.chartConfigs.dirChart = {
                type: 'bar',
                data: {
                    labels: dirData.map(item => item.label),
                    datasets: [{
                        label: 'Arquivos',
                        data: dirData.map(item => item.value),
                        backgroundColor: '#10b981',
                        borderWidth: 0
                    }]
                },
                options: {
                    indexAxis: 'y',
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: false
                        },
                        tooltip: {
                            backgroundColor: '#1f2937',
                            titleColor: '#93c5fd',
                            bodyColor: '#f3f4f6',
                            borderColor: '#3b82f6',
                            borderWidth: 1,
                            padding: 10,
                            boxPadding: 5
                        }
                    },
                    scales: {
                        x: {
                            beginAtZero: true,
                            grid: {
                                color: 'rgba(243, 244, 246, 0.1)'
                            },
                            ticks: {
                                color: '#d1d5db'
                            }
                        },
                        y: {
                            grid: {
                                display: false
                            },
                            ticks: {
                                color: '#d1d5db'
                            }
                        }
                    }
                }
            };
            
            const dirCtx = document.getElementById('dirChart').getContext('2d');
            new Chart(dirCtx, window.chartConfigs.dirChart);
'@

    # CORREÇÃO: Função para inicializar eventos após o carregamento da página
    $windowLoadInit = @'
            // CORREÇÃO: Verificar e corrigir inconsistências no carregamento inicial
            window.addEventListener('load', function() {
                console.log("Página carregada completamente");
                setTimeout(function() {
                    restoreCheckboxState();
                    updateProgressDisplay();
                    
                    // CORREÇÃO: Configurar manipuladores de eventos para paginação
                    setupPaginationHandlers();
                    
                    // Iniciar verificação periódica
                    setInterval(verifyProgressState, 5000);
                }, 1500);
            });
            
            // CORREÇÃO: Adicionar evento para quando o DOM estiver pronto
            $(document).ready(function() {
                console.log("DOM pronto");
                setTimeout(setupPaginationHandlers, 1000);
                
                // Configurar delegação de eventos global para paginação
                $(document).off('click', '.paginate_button, .paginate_button.previous, .paginate_button.next').on('click', '.paginate_button, .paginate_button.previous, .paginate_button.next', function(e) {
                    console.log("Clique em botão de paginação via delegação global");
                    setTimeout(function() {
                        restoreCheckboxState();
                        updateProgressDisplay();
                    }, 300);
                });
            });
'@

    # CORREÇÃO: Código de manipulador para botões "Copiar"
    $copyButtonHandler = @'
        // Função para copiar texto para a área de transferência
        function copyToClipboard(elementId) {
            const element = document.getElementById(elementId);
            const text = element.innerText || element.textContent;
            
            // CORREÇÃO: Usar método moderno com Promise
            if (navigator.clipboard && window.isSecureContext) {
                // Para contextos seguros (HTTPS)
                navigator.clipboard.writeText(text)
                    .then(() => {
                        showCopyNotification();
                    })
                    .catch(err => {
                        console.error('Erro ao copiar texto: ', err);
                        fallbackCopyTextToClipboard(text);
                    });
            } else {
                // Fallback para contextos não seguros
                fallbackCopyTextToClipboard(text);
            }
        }
        
        // Fallback para navegadores mais antigos
        function fallbackCopyTextToClipboard(text) {
            const textArea = document.createElement("textarea");
            textArea.value = text;
            
            // Tornar invisível mas manter na tela
            textArea.style.position = "fixed";
            textArea.style.left = "-999999px";
            textArea.style.top = "-999999px";
            document.body.appendChild(textArea);
            textArea.focus();
            textArea.select();
            
            try {
                document.execCommand('copy');
                showCopyNotification();
            } catch (err) {
                console.error('Fallback: Erro ao copiar texto', err);
                alert('Não foi possível copiar o texto. Seu navegador pode não suportar esta funcionalidade.');
            }
            
            document.body.removeChild(textArea);
        }
        
        // Mostrar notificação de cópia
        function showCopyNotification() {
            const notification = document.getElementById('copyNotification');
            notification.classList.add('show');
            
            // Esconder notificação após 2 segundos
            setTimeout(() => {
                notification.classList.remove('show');
            }, 2000);
        }
'@

    # CORREÇÃO: Código para lidar com mudanças de página na tabela
    $tablePageChangeHandler = @'
        // Adicionar evento para mudanças de página
        function handleTablePageChange() {
            console.log("Manipulador de mudança de página chamado");
            restoreCheckboxState();
            updateProgressDisplay();
        }
        
        // CORREÇÃO: Função para toggle em linhas
        function toggleRowDone(checkbox, rowId) {
            console.log(`Toggle row: ${rowId}, checked: ${checkbox.checked}`);
            const row = document.getElementById(rowId);
            
            if (checkbox.checked) {
                row.classList.add('file-done');
            } else {
                row.classList.remove('file-done');
            }
            
            // Salvar estado no localStorage
            saveCheckboxState();
            
            // Atualizar o gráfico de progresso
            updateProgressDisplay();
        }
'@

    # CORREÇÃO: Adicionar estilos CSS para resolver o problema da tabela
    $additionalStyles = @'
    /* CORREÇÃO: Melhorar estabilidade da tabela */
    .dataTables_wrapper {
        overflow-x: auto;
        width: 100%;
    }

    table.dataTable {
        width: 100% !important;
        table-layout: fixed;
    }

    table.dataTable th, 
    table.dataTable td {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }

    /* CORREÇÃO: Ajustar coluna de caminho completo para permitir quebra de linha quando necessário */
    table.dataTable td:nth-child(4) {
        white-space: normal;
        word-break: break-all;
    }

    /* CORREÇÃO: Ajustar coluna de tamanho para alinhar à direita */
    table.dataTable td:last-child {
        text-align: right;
        width: 120px !important;
    }

    /* CORREÇÃO: Garantir que o conteúdo da tabela não quebre o layout */
    .overflow-x-auto {
        min-width: 100%;
    }

    /* CORREÇÃO: Ajustar estilo de paginação para melhor usabilidade */
    .dataTables_length select {
        min-width: 60px;
    }
    
    /* NOVA ADIÇÃO: Estilo para legenda de categorias de tamanho */
    .size-categories-legend {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        margin-top: 15px;
        gap: 8px;
    }
    
    .size-category-item {
        display: flex;
        align-items: center;
        margin-right: 10px;
    }
    
    .size-category-color {
        width: 16px;
        height: 16px;
        border-radius: 3px;
        margin-right: 5px;
    }
    
    .size-category-label {
        font-size: 12px;
        color: #d1d5db;
    }
    
    /* CORREÇÃO: Melhorar estilo dos botões de paginação */
    .dataTables_paginate .paginate_button {
        position: relative;
        display: inline-block;
        min-width: 32px !important;
        text-align: center !important;
        cursor: pointer !important;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3) !important;
        margin: 0 4px !important;
        border-radius: 4px !important;
        font-weight: 500 !important;
        background-color: #1f2937 !important;
        color: #ffffff !important;
        padding: 6px 12px !important;
        user-select: none !important;
        z-index: 10 !important;
    }
    
    .dataTables_paginate .paginate_button.current {
        background: linear-gradient(to bottom, #3b82f6, #1e40af) !important;
        color: #ffffff !important;
        font-weight: bold !important;
        box-shadow: 0 0 10px rgba(59, 130, 246, 0.5) !important;
        z-index: 20 !important;
    }
    
    .dataTables_paginate .paginate_button:hover:not(.disabled):not(.current) {
        background: linear-gradient(to bottom, #60a5fa, #3b82f6) !important;
        color: #ffffff !important;
        border: 1px solid #93c5fd !important;
        transition: all 0.2s ease !important;
        transform: translateY(-1px) !important;
    }
    
    .dataTables_paginate .paginate_button.disabled {
        opacity: 0.5 !important;
        cursor: not-allowed !important;
    }
    
    /* CORREÇÃO: Aumentar tamanho dos controles para dispositivos touch */
    @media (max-width: 768px) {
        .dataTables_paginate .paginate_button {
            min-width: 40px !important;
            padding: 8px 14px !important;
            margin: 0 5px !important;
        }
    }
'@

    # Gerar HTML com tema escuro
    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Relatório de Comparação: $folder1Name vs $folder2Name</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/datatables/1.10.21/js/jquery.dataTables.min.js"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/datatables/1.10.21/css/jquery.dataTables.min.css">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
        }
        body {
            background-color: #111827;
            color: #f3f4f6;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .flex {
            display: flex;
        }
        .flex-col {
            flex-direction: column;
        }
        .space-y-6 > * + * {
            margin-top: 1.5rem;
        }
        .p-6 {
            padding: 1.5rem;
        }
        .bg-gray-900 {
            background-color: #0f172a; /* Um pouco mais escuro para aumentar o contraste */
        }
        .rounded-lg {
            border-radius: 0.5rem;
        }
        .text-gray-100 {
            color: #f3f4f6;
        }
        .justify-between {
            justify-content: space-between;
        }
        .items-center {
            align-items: center;
        }
        .text-2xl {
            font-size: 1.5rem;
        }
        .font-bold {
            font-weight: 700;
        }
        .text-blue-300 {
            color: #60a5fa; /* Mais brilhante que o original #93c5fd */
        }
        .bg-blue-900 {
            background-color: #1e40af; /* Mais vibrante que o original #1e3a8a */
        }
        .text-blue-100 {
            color: #dbeafe;
        }
        .px-4 {
            padding-left: 1rem;
            padding-right: 1rem;
        }
        .py-2 {
            padding-top: 0.5rem;
            padding-bottom: 0.5rem;
        }
        .text-sm {
            font-size: 0.875rem;
        }
        .font-semibold {
            font-weight: 600;
        }
        .bg-gray-800 {
            background-color: #1a2234; /* Um pouco mais claro que o original #1f2937 */
        }
        .p-4 {
            padding: 1rem;
        }
        .p-3 {
            padding: 0.75rem;
        }
        .text-xl {
            font-size: 1.25rem;
        }
        .mb-4 {
            margin-bottom: 1rem;
        }
        .mb-8 {
            margin-bottom: 2rem;
        }
        .mb-6 {
            margin-bottom: 1.5rem;
        }
        .mb-2 {
            margin-bottom: 0.5rem;
        }
        .mb-1 {
            margin-bottom: 0.25rem;
        }
        .relative {
            position: relative;
        }
        .text-center {
            text-align: center;
        }
        .grid {
            display: grid;
        }
        .gap-3 {
            gap: 0.75rem;
        }
        .gap-4 {
            gap: 1rem;
        }
        .gap-6 {
            gap: 1.5rem;
        }
        .bg-gray-700 {
            background-color: #374151;
        }
        .border-l-4 {
            border-left-width: 4px;
        }
        .border-green-500 {
            border-left-color: #10b981;
        }
        .border-yellow-500 {
            border-left-color: #f59e0b;
        }
        .border-blue-500 {
            border-left-color: #3b82f6;
        }
        .text-green-400 {
            color: #34d399;
        }
        .text-xs {
            font-size: 0.75rem;
        }
        .text-gray-300 {
            color: #d1d5db;
        }
        .text-gray-400 {
            color: #9ca3af;
        }
        .border-collapse {
            border-collapse: collapse;
        }
        .border-b {
            border-bottom-width: 1px;
        }
        .border-gray-600 {
            border-color: #4b5563;
        }
        .text-left {
            text-align: left;
        }
        .text-right {
            text-align: right;
        }
        .h-64 {
            height: 16rem;
        }
        
        /* DataTables overwrites - CORRIGIDO */
        .dataTables_wrapper {
            color: #f3f4f6;
            padding: 0;
            margin-bottom: 15px;
        }
        .dataTables_length, .dataTables_filter {
            padding: 8px 0;
            margin-bottom: 10px;
        }
        .dataTables_length select, .dataTables_filter input {
            background-color: #374151;
            color: #f3f4f6;
            border: 1px solid #4b5563;
            border-radius: 4px;
            padding: 4px 8px;
        }
        
        /* CORREÇÃO: Melhorar visibilidade dos controles de paginação */
        .dataTables_info, .dataTables_paginate {
            padding: 12px 0;
            color: #d1d5db;
            font-size: 14px;
            margin-top: 10px;
        }
        .dataTables_paginate {
            display: flex;
            justify-content: flex-end;
            align-items: center;
        }
        .dataTables_paginate .paginate_button {
            color: #ffffff !important; /* Branco puro para maior contraste */
            border: 1px solid #4b5563 !important;
            border-radius: 4px;
            background: #1f2937 !important;
            margin: 0 4px; /* Mais espaçamento entre botões */
            padding: 6px 12px !important; /* Botões maiores */
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3) !important; /* Sombra para melhorar a legibilidade */
            font-weight: 500 !important;
            min-width: 32px !important; /* Largura mínima para botões */
            text-align: center !important;
            cursor: pointer !important;
        }
        .dataTables_paginate .paginate_button.current {
            color: #ffffff !important;
            background: linear-gradient(to bottom, #3b82f6, #1e40af) !important; /* Gradiente azul */
            border: 1px solid #60a5fa !important;
            box-shadow: 0 0 10px rgba(59, 130, 246, 0.5) !important; /* Brilho azul */
            font-weight: bold !important;
        }
        .dataTables_paginate .paginate_button:hover {
            color: #ffffff !important;
            background: linear-gradient(to bottom, #60a5fa, #3b82f6) !important; /* Gradiente mais brilhante */
            border: 1px solid #93c5fd !important;
            box-shadow: 0 0 15px rgba(96, 165, 250, 0.6) !important; /* Brilho mais intenso */
            transform: translateY(-1px) !important; /* Leve efeito de elevação */
            transition: all 0.2s !important;
        }
        .dataTables_paginate .ellipsis {
            color: #ffffff !important;
            font-weight: bold !important;
            font-size: 18px !important;
            padding: 0 5px !important;
            text-shadow: 0 0 3px rgba(255, 255, 255, 0.5) !important; /* Sombra para realçar */
        }
        
        /* CORREÇÃO: Garantir que a paginação seja exibida corretamente */
        .dataTables_paginate .previous,
        .dataTables_paginate .next {
            display: inline-block !important;
        }
        
        /* Card shadow */
        .card-shadow {
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.3), 0 2px 4px -1px rgba(0, 0, 0, 0.2);
        }
        
        /* Alternating table rows */
        tr.row-odd {
            background-color: #2d3748;
        }
        tr.row-even {
            background-color: #1e293b;
        }
        
        /* Stats badge */
        .stats-badge {
            background-color: #1e40af; /* Mais vibrante */
            color: #dbeafe;
            padding: 0.5rem 1rem;
            border-radius: 0.5rem;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
            font-weight: 600;
        }
        
        .stats-badge .text-red-500 {
            color: #ef4444;
            text-shadow: 0 0 5px rgba(239, 68, 68, 0.5);
        }
        
        /* Path card */
        .path-card {
            background-color: #1a2234; /* Um pouco mais claro */
            padding: 0.75rem;
            border-radius: 0.375rem;
            margin-bottom: 0.5rem;
            border-left: 4px solid #3b82f6;
            word-break: break-all;
        }
        
        /* Summary card */
        .summary-card {
            background-color: #374151;
            padding: 1rem;
            border-radius: 0.5rem;
            box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
        }
        .summary-card h3 {
            color: #60a5fa; /* Mais brilhante */
            font-size: 0.875rem;
            margin-bottom: 0.25rem;
        }
        .summary-card p {
            font-size: 1.5rem;
            font-weight: 700;
            color: #f3f4f6;
        }
        .summary-card .text-red-500 {
            color: #ef4444 !important;
        }
        
        /* Section description */
        .section-description {
            color: #d1d5db;
            font-size: 0.875rem;
            margin-bottom: 1rem;
            line-height: 1.5;
        }
        
        /* Grid responsive */
        @media (min-width: 768px) {
            .grid-cols-2 {
                grid-template-columns: repeat(2, minmax(0, 1fr));
            }
            .grid-cols-4 {
                grid-template-columns: repeat(4, minmax(0, 1fr));
            }
        }

        /* Override DataTables dark mode conflict */
        table.dataTable tbody tr {
            background-color: transparent;
        }
        
        .dataTables_wrapper .dataTables_length, 
        .dataTables_wrapper .dataTables_filter, 
        .dataTables_wrapper .dataTables_info, 
        .dataTables_wrapper .dataTables_processing, 
        .dataTables_wrapper .dataTables_paginate {
            color: #d1d5db;
        }
        
        /* Copy button */
        .copy-btn {
            display: flex;
            align-items: center;
            gap: 0.25rem;
            background-color: #1e40af; /* Mais vibrante */
            color: #dbeafe;
            padding: 0.25rem 0.5rem;
            border-radius: 0.25rem;
            font-size: 0.75rem;
            cursor: pointer;
            transition: background-color 0.2s;
        }
        .copy-btn:hover {
            background-color: #2563eb;
        }
        .copy-btn svg {
            width: 14px;
            height: 14px;
        }
        
        /* Copy notification */
        .copy-notification {
            position: fixed;
            top: 20px;
            right: 20px;
            background-color: #059669;
            color: white;
            padding: 0.5rem 1rem;
            border-radius: 0.25rem;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            opacity: 0;
            transform: translateY(-20px);
            transition: opacity 0.3s, transform 0.3s;
            z-index: 1000;
        }
        .copy-notification.show {
            opacity: 1;
            transform: translateY(0);
        }
        
        /* Tabela com botões de cópia */
        .copy-cell-btn {
            background-color: transparent;
            color: #60a5fa; /* Mais brilhante */
            border: none;
            cursor: pointer;
            padding: 2px 5px;
            border-radius: 3px;
            font-size: 12px;
            display: inline-flex;
            align-items: center;
            margin-left: 5px;
            opacity: 0.5;
            transition: opacity 0.2s, background-color 0.2s;
        }
        tr:hover .copy-cell-btn {
            opacity: 1;
        }
        .copy-cell-btn:hover {
            background-color: rgba(59, 130, 246, 0.2);
        }
        
        /* Estilo para linhas marcadas como concluídas */
        tr.file-done {
            background-color: rgba(16, 185, 129, 0.2) !important; /* Verde com transparência */
        }
        tr.file-done td {
            color: #34d399 !important; /* Texto verde mais claro */
        }
        
        /* Estilo para o checkbox */
        .file-check {
            accent-color: #10b981;
            transform: scale(1.2);
        }
        
        /* Estilo para créditos */
        .developer-credit {
            margin-top: 0.5rem;
            font-weight: 500;
            color: #60a5fa;
            letter-spacing: 0.5px;
        }
        
        /* NOVO ESTILO - Barra de Progresso Avançada */
        .progress-container {
            position: relative;
            height: 180px;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            margin: 20px 0;
        }
        
        .progress-bar-container {
            width: 100%;
            height: 30px;
            background-color: #1f2937;
            border-radius: 15px;
            position: relative;
            overflow: hidden;
            box-shadow: inset 0 0 10px rgba(0, 0, 0, 0.3);
            margin-bottom: 25px;
        }
        
        .progress-bar {
            height: 100%;
            background: linear-gradient(to right, #10b981, #34d399);
            border-radius: 15px;
            transition: width 0.5s ease;
            width: 0%;
            box-shadow: 0 0 10px rgba(16, 185, 129, 0.5);
        }
        
        .progress-details {
            display: flex;
            justify-content: space-between;
            width: 100%;
            margin-top: 10px;
        }
        
        .progress-stat {
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 10px 15px;
            background-color: #2d3748;
            border-radius: 8px;
            width: 48%;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
        }
        
        .progress-stat.pending {
            border-left: 4px solid #ef4444;
        }
        
        .progress-stat.complete {
            border-left: 4px solid #10b981;
        }
        
        .progress-stat-title {
            font-size: 0.8rem;
            color: #d1d5db;
            margin-bottom: 5px;
        }
        
        .progress-stat-value {
            font-size: 1.5rem;
            font-weight: bold;
        }
        
        .pending .progress-stat-value {
            color: #ef4444;
        }
        
        .complete .progress-stat-value {
            color: #10b981;
        }
        
        .progress-percentage-display {
            position: absolute;
            top: -5px;
            left: 50%;
            transform: translateX(-50%);
            background: linear-gradient(to bottom, #3b82f6, #1e40af);
            color: white;
            font-weight: bold;
            font-size: 1.1rem;
            padding: 5px 15px;
            border-radius: 20px;
            box-shadow: 0 2px 10px rgba(59, 130, 246, 0.4);
            z-index: 5;
            min-width: 80px;
            text-align: center;
        }
        
        /* Progress animation */
        @keyframes pulse {
            0% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7); }
            70% { box-shadow: 0 0 0 10px rgba(16, 185, 129, 0); }
            100% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }
        }
        
        .progress-bar.pulse {
            animation: pulse 2s infinite;
        }
        
        /* Progress stats icons */
        .progress-stat-icon {
            font-size: 1.5rem;
            margin-bottom: 5px;
        }
        
        .pending .progress-stat-icon {
            color: #ef4444;
        }
        
        .complete .progress-stat-icon {
            color: #10b981;
        }
        
        $additionalStyles
    </style>
</head>
<body>
    <div class="container">
        <div class="flex flex-col space-y-6 p-6 bg-gray-900 rounded-lg text-gray-100">
            <div class="flex justify-between items-center">
                <h1 class="text-2xl font-bold text-blue-300">Relatório de Comparação: $folder1Name vs $folder2Name</h1>
                <div class="stats-badge">
                    Total: <span id="totalFiles" class="text-red-500 font-bold">$formattedUniqueFiles</span> arquivos ausentes na Pasta 2
                </div>
            </div>
            
            <p class="section-description">
                Este relatório apresenta os arquivos encontrados apenas na Pasta 1 e não presentes na Pasta 2.
                Ele é gerado através da comparação entre os dois caminhos analisados, identificando quais arquivos precisam ser sincronizados.
            </p>
            
            <!-- Caminhos analisados -->
            <div class="bg-gray-800 p-4 rounded-lg card-shadow">
                <h2 class="text-xl font-bold mb-2 text-blue-300">Caminhos Analisados</h2>
                <p class="section-description">
                    Abaixo estão os caminhos usados para a análise de arquivos. A comparação verifica quais arquivos existem na Pasta 1 mas não foram encontrados na Pasta 2.
                </p>
                <div class="grid grid-cols-1 gap-3">
                    <div class="path-card">
                        <div class="flex justify-between items-center">
                            <h3 class="text-sm font-semibold text-blue-300 mb-1">Pasta 1:</h3>
                            <button onclick="copyToClipboard('folder1Path')" class="copy-btn">
                                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                    <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                                    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
                                </svg>
                                Copiar
                            </button>
                        </div>
                        <p id="folder1Path" class="text-gray-300">$Folder1Path</p>
                    </div>
                    
                    <div class="path-card">
                        <div class="flex justify-between items-center">
                            <h3 class="text-sm font-semibold text-blue-300 mb-1">Pasta 2:</h3>
                            <button onclick="copyToClipboard('folder2Path')" class="copy-btn">
                                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                    <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                                    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
                                </svg>
                                Copiar
                            </button>
                        </div>
                        <p id="folder2Path" class="text-gray-300">$Folder2Path</p>
                    </div>
                </div>
            </div>
            
            <!-- Resumo da análise -->
            <div class="bg-gray-800 p-4 rounded-lg card-shadow">
                <h2 class="text-xl font-bold mb-2 text-blue-300">Resumo da Análise</h2>
                <p class="section-description">
                    Resumo quantitativo da análise de arquivos. "Arquivos Ausentes" representa o número de arquivos encontrados na Pasta 1 mas que não existem na Pasta 2.
                </p>
                <div class="grid grid-cols-2 grid-cols-4 gap-4">
                    <div class="summary-card">
                        <h3>Total Analisado</h3>
                        <p id="totalAnalyzed">$formattedTotalAnalyzed</p>
                    </div>
                    
                    <div class="summary-card">
                        <h3>Arquivos Ausentes</h3>
                        <p id="uniqueFiles" class="text-red-500">$formattedUniqueFiles</p>
                    </div>
                    
                    <div class="summary-card">
                        <h3>Tamanho Total</h3>
                        <p id="totalSize">$formattedTotalSize</p>
                    </div>
                    
                    <div class="summary-card">
                        <h3>Duração Total da Análise</h3>
                        <p id="processingTime">$formattedTime</p>
                    </div>
                </div>
            </div>
            
            <!-- Gráficos de análise -->
            <div class="grid grid-cols-1 grid-cols-2 gap-6">
                <div class="bg-gray-800 p-4 rounded-lg card-shadow">
                    <h2 class="text-xl font-bold mb-2 text-blue-300">Distribuição por Tamanho</h2>
                    <p class="section-description">
                        Mostra como os arquivos ausentes estão distribuídos nas categorias de tamanho.
                    </p>
                    <div class="h-64">
                        <canvas id="sizeChart"></canvas>
                    </div>
                    <!-- Legenda de cores para o gráfico de tamanho -->
                    <div class="size-categories-legend">
                        <div class="size-category-item">
                            <div class="size-category-color" style="background-color: #A86BD2;"></div>
                            <div class="size-category-label">0B a 10KB</div>
                        </div>
                        <div class="size-category-item">
                            <div class="size-category-color" style="background-color: #1E90FF;"></div>
                            <div class="size-category-label">10KB a 100KB</div>
                        </div>
                        <div class="size-category-item">
                            <div class="size-category-color" style="background-color: #32CD32;"></div>
                            <div class="size-category-label">100KB a 10MB</div>
                        </div>
                        <div class="size-category-item">
                            <div class="size-category-color" style="background-color: #FFA500;"></div>
                            <div class="size-category-label">10MB a 1GB</div>
                        </div>
                        <div class="size-category-item">
                            <div class="size-category-color" style="background-color: #FF0000;"></div>
                            <div class="size-category-label">Acima de 1GB</div>
                        </div>
                    </div>
                </div>
                
                <div class="bg-gray-800 p-4 rounded-lg card-shadow">
                    <h2 class="text-xl font-bold mb-2 text-blue-300">Top 10 Extensões</h2>
                    <p class="section-description">
                        Apresenta as 10 extensões de arquivo mais comuns entre os arquivos exclusivos. Útil para identificar quais tipos de conteúdo precisam ser sincronizados com maior frequência.
                    </p>
                    <div class="h-64">
                        <canvas id="extensionChart"></canvas>
                    </div>
                </div>
            </div>
            
            <!-- Gráficos: Arquivos por Diretório e Progresso -->
            <div class="grid grid-cols-1 grid-cols-2 gap-6">
                <div class="bg-gray-800 p-4 rounded-lg card-shadow">
                    <h2 class="text-xl font-bold mb-2 text-blue-300">Top 5 Arquivos por Diretório</h2>
                    <p class="section-description">
                        Identifica quais subpastas contêm a maior quantidade de arquivos exclusivos. Ajuda a visualizar quais pastas precisam de atenção prioritária na sincronização de dados.
                    </p>
                    <div class="h-64">
                        <canvas id="dirChart"></canvas>
                    </div>
                </div>
                
                <div class="bg-gray-800 p-4 rounded-lg card-shadow">
                    <h2 class="text-xl font-bold mb-2 text-blue-300">Progresso de Sincronização</h2>
                    <p class="section-description">
                        Acompanhe o progresso da sincronização dos arquivos. Use os checkboxes na tabela abaixo para marcar os arquivos que já foram processados.
                    </p>
                    
                    <!-- NOVO MODELO DE PROGRESSO -->
                    <div class="progress-container">
                        <div class="progress-percentage-display" id="progressPercentage">0%</div>
                        
                        <div class="progress-bar-container">
                            <div class="progress-bar" id="progressBar"></div>
                        </div>
                        
                        <div class="progress-details">
                            <div class="progress-stat pending">
                                <div class="progress-stat-icon">⚠️</div>
                                <div class="progress-stat-title">Pendentes</div>
                                <div class="progress-stat-value" id="pendingFiles">$formattedUniqueFiles</div>
                            </div>
                            
                            <div class="progress-stat complete">
                                <div class="progress-stat-icon">✅</div>
                                <div class="progress-stat-title">Concluídos</div>
                                <div class="progress-stat-value" id="completedFiles">0</div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Tabela de arquivos -->
            <div class="bg-gray-800 p-4 rounded-lg card-shadow">
                <h2 class="text-xl font-bold mb-2 text-blue-300">Lista de Arquivos Ausentes na Pasta 2</h2>
                <p class="section-description">
                    Esta tabela apresenta todos os arquivos que existem na Pasta 1 mas não foram encontrados na Pasta 2. 
                    Use os checkboxes para marcar os arquivos que já foram processados ou sincronizados.
                </p>
                <div class="overflow-x-auto">
                    <table id="filesTable" class="min-w-full border-collapse">
                        <thead>
                            <tr>
                                <th class="p-3 border-b border-gray-600 bg-gray-800 text-center font-medium text-blue-300" style="width: 50px;">Ação</th>
                                <th class="p-3 border-b border-gray-600 bg-gray-800 text-left font-medium text-blue-300">#</th>
                                <th class="p-3 border-b border-gray-600 bg-gray-800 text-left font-medium text-blue-300">Nome do Arquivo</th>
                                <th class="p-3 border-b border-gray-600 bg-gray-800 text-left font-medium text-blue-300">Caminho Completo</th>
                                <th class="p-3 border-b border-gray-600 bg-gray-800 text-right font-medium text-blue-300">Tamanho</th>
                            </tr>
                        </thead>
                        <tbody>
                            $tableRows
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div class="text-center text-gray-400 text-sm">
                Relatório gerado em <span id="reportDate">$reportDate</span> | Comparador de Pastas
                <br><span class="developer-credit">Desenvolvido por Mathews Buzetti</span>
            </div>
        </div>
    </div>
    
    <div id="copyNotification" class="copy-notification">Copiado para a área de transferência!</div>
    
    <script>
        // CORREÇÃO: Melhorar manipulador de eventos para funcionar em todos os navegadores
        $copyButtonHandler
        
        // CORREÇÃO: Função para alternar estado de linha e salvar estado
        $tablePageChangeHandler
        
        $saveCheckboxState
        
        $restoreCheckboxState
        
        $updateProgressCode
        
        $verifyProgressState
        
        // CORREÇÃO: Adicionar manipulador de eventos para paginação
        $paginationHandler
        
        // Inicialização dos gráficos com dados dinâmicos
        document.addEventListener('DOMContentLoaded', function() {
            $chartInitCode
            
            // Dados diretamente no JavaScript
            const extensionData = $extensionChartJson;
            const sizeData = $sizeRangesChartJson;
            const dirData = $dirChartJson;
            
            console.log('Dados de extensões:', extensionData);
            console.log('Dados de tamanhos:', sizeData);
            console.log('Dados de diretórios:', dirData);
            
            // Cores para os outros gráficos - MAIS VIBRANTES
            const colors = [
                '#3b82f6', '#10b981', '#8b5cf6', '#ef4444', '#f59e0b',
                '#06b6d4', '#6366f1', '#14b8a6', '#ec4899', '#f97316'
            ];
            
            // Opções comuns para os gráficos
            const commonOptions = {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'right',
                        labels: {
                            color: '#f3f4f6',
                            font: {
                                size: 12
                            }
                        }
                    },
                    tooltip: {
                        backgroundColor: '#1f2937',
                        titleColor: '#93c5fd',
                        bodyColor: '#f3f4f6',
                        borderColor: '#3b82f6',
                        borderWidth: 1,
                        padding: 10,
                        boxPadding: 5,
                        bodyFont: {
                            size: 13
                        },
                        titleFont: {
                            size: 14,
                            weight: 'bold'
                        }
                    }
                }
            };
            
            $saveSizeChartData
            
            $dataTablesInitCode
        });
        
        $windowLoadInit
    </script>
</body>
</html>
"@
    
    # Salvar HTML - Sem exibir mensagem no console
    try {
        # Garantir pasta de destino
        $outputDir = Split-Path -Path $OutputHTMLFile -Parent
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Exportar HTML
        $html | Out-File -FilePath $OutputHTMLFile -Encoding utf8
        
        # Tentar abrir o relatório no navegador
        try {
            Start-Process $OutputHTMLFile
        }
        catch {
            # Silenciosamente ignorar erros ao abrir o navegador
        }
    }
    catch {
        Write-Host "`n[ERRO AO GERAR RELATÓRIO HTML]" -ForegroundColor Red
        Write-Host "└─ Erro: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Compare-FolderPairs {
    param(
        [array]$FolderPairs,
        [string]$OutputDir = "C:\temp",
        [switch]$HandleLongPaths = $false,
        [switch]$UseParallel = $true,
        [int]$MaxThreads = 0
    )
    
    # Verificar se a lista de pares está vazia
    if ($FolderPairs.Count -eq 0) {
        Write-Host "`n[ERRO] Nenhum par de pastas fornecido para comparação." -ForegroundColor Red
        return
    }
    
    # Garantir que a pasta de saída existe
    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    
    # Processar cada par de pastas
    foreach ($pair in $FolderPairs) {
        $folder1Path = $pair.Folder1
        $folder2Path = $pair.Folder2
        
        Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║  INICIANDO COMPARAÇÃO: $(Split-Path -Path $folder1Path -Leaf) vs $(Split-Path -Path $folder2Path -Leaf)" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        
        # Gerar nome de arquivo para o relatório HTML
        $htmlFile = Generate-FileName -Folder1Path $folder1Path -Folder2Path $folder2Path -Extension ".html" -BasePath $OutputDir
        
        # Chamar a função de comparação para este par
        Compare-Folders -Folder1Path $folder1Path -Folder2Path $folder2Path `
                       -HTMLReport $htmlFile `
                       -HandleLongPaths:$HandleLongPaths -UseParallel:$UseParallel -MaxThreads $MaxThreads
    }
}

function Compare-Folders {
    param(
        [string]$Folder1Path,
        [string]$Folder2Path,
        [string]$HTMLReport = "",
        [switch]$HandleLongPaths = $false,
        [switch]$UseParallel = $true,
        [int]$MaxThreads = 0,
        [switch]$ShowDebug = $false  # Novo parâmetro para controlar mensagens de debug
    )
    
    # Detectar PowerShell ISE
    $isISE = $null -ne $psISE
    
    # Se estiver no ISE, usar modo otimizado para ISE
    if ($isISE) {
        $UseParallel = $false
    }
    # Se não, verificar versão do PowerShell para compatibilidade com paralelo
    else {
        $psVersion = $PSVersionTable.PSVersion.Major
        $supportsParallel = $psVersion -ge 7
        
        # Se não suporta paralelo, desativar independente da solicitação
        if (-not $supportsParallel -and $UseParallel) {
            $UseParallel = $false
            Write-Host "Processamento paralelo requer PowerShell 7+. Usando modo sequencial." -ForegroundColor Yellow
        }
    }
    
    # Se MaxThreads não for especificado, usar o padrão
    if ($MaxThreads -le 0) {
        $MaxThreads = $global:defaultMaxThreads
    }
    
    # CORREÇÃO: Registrar tempo de início e garantir que ele seja capturado corretamente
    $startTime = [DateTime]::Now
    $global:scriptStartTime = $startTime
    
    # Tratar caminhos longos se necessário
    if ($HandleLongPaths) {
        $Folder1Path = Enable-LongPaths -Path $Folder1Path
        $Folder2Path = Enable-LongPaths -Path $Folder2Path
    }
    
    # Verificar pastas
    Write-Host "`n[VERIFICANDO PASTAS]" -ForegroundColor Yellow
    $folder1Accessible = Test-Path $Folder1Path
    $folder2Accessible = Test-Path $Folder2Path
    
    Write-Host "├─ Pasta 1: " -NoNewline -ForegroundColor DarkGray
    if ($folder1Accessible) {
        Write-Host "✓ OK" -ForegroundColor Green
        Write-Host "│  └─ $Folder1Path" -ForegroundColor DarkCyan
    } else {
        Write-Host "✗ INACESSÍVEL" -ForegroundColor Red
        Write-Host "│  └─ Erro: Pasta 1 não encontrada ou sem permissão" -ForegroundColor Red
        return
    }
    
    Write-Host "└─ Pasta 2: " -NoNewline -ForegroundColor DarkGray
    if ($folder2Accessible) {
        Write-Host "✓ OK" -ForegroundColor Green
        Write-Host "   └─ $Folder2Path" -ForegroundColor DarkGreen
    } else {
        Write-Host "✗ INACESSÍVEL" -ForegroundColor Red
        Write-Host "   └─ Erro: Pasta 2 não encontrada ou sem permissão" -ForegroundColor Red
        return
    }
    
    # Escanear arquivos da Pasta 1
    Write-Host "`n[ESCANEANDO ARQUIVOS DA PASTA 1]" -ForegroundColor Yellow
    $scanFolder1Start = [DateTime]::Now
    
    try {
        # Detectar PowerShell ISE
        $isISE = $null -ne $psISE
        
        if ($isISE) {
            # Usar abordagem específica para o ISE
            $global:folder1Files = Scan-DirectoriesISE -BasePath $Folder1Path -Stage "Escaneando" -FolderLabel "Pasta 1"
        }
        elseif ($UseParallel) {
            Write-Host "Usando processamento paralelo com $MaxThreads threads..." -ForegroundColor Cyan
            $global:folder1Files = Scan-DirectoriesParallel -BasePath $Folder1Path -MaxThreads $MaxThreads -Stage "Escaneando" -FolderLabel "Pasta 1"
        } else {
            Write-Host "Usando processamento sequencial..." -ForegroundColor Yellow
            $global:folder1Files = Get-ChildItem -Path $Folder1Path -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable getFileErrors
            
            if ($getFileErrors.Count -gt 0) {
                Write-Host "Avisos de acesso (primeiros 5):" -ForegroundColor Yellow
                $getFileErrors | Select-Object -First 5 | ForEach-Object {
                    Write-Host "  - Não foi possível acessar: $($_.TargetObject)" -ForegroundColor DarkYellow
                }
                if ($getFileErrors.Count -gt 5) {
                    Write-Host "  - ... e mais $($getFileErrors.Count - 5) arquivos/pastas" -ForegroundColor DarkYellow
                }
            }
        }
    }
    catch {
        Write-Host "`n[ERRO] Falha ao escanear arquivos da Pasta 1: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # Escanear arquivos da Pasta 2
    Write-Host "`n[ESCANEANDO ARQUIVOS DA PASTA 2]" -ForegroundColor Yellow
    $scanFolder2Start = [DateTime]::Now
    
    try {
        if ($isISE) {
            # Usar abordagem específica para o ISE
            $global:folder2Files = Scan-DirectoriesISE -BasePath $Folder2Path -Stage "Escaneando" -FolderLabel "Pasta 2"
        }
        elseif ($UseParallel) {
            $global:folder2Files = Scan-DirectoriesParallel -BasePath $Folder2Path -MaxThreads $MaxThreads -Stage "Escaneando" -FolderLabel "Pasta 2"
        } else {
            $global:folder2Files = Get-ChildItem -Path $Folder2Path -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable getFileErrors
            
            if ($getFileErrors.Count -gt 0) {
                Write-Host "Avisos de acesso (primeiros 5):" -ForegroundColor Yellow
                $getFileErrors | Select-Object -First 5 | ForEach-Object {
                    Write-Host "  - Não foi possível acessar: $($_.TargetObject)" -ForegroundColor DarkYellow
                }
                if ($getFileErrors.Count -gt 5) {
                    Write-Host "  - ... e mais $($getFileErrors.Count - 5) arquivos/pastas" -ForegroundColor DarkYellow
                }
            }
            
            Show-AdvancedProgress -Stage "Pasta 2" -Current $global:folder2Files.Count -Total $global:folder2Files.Count -StartTime $scanFolder2Start
        }
    }
    catch {
        Write-Host "`n[ERRO] Falha ao escanear arquivos da Pasta 2: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # Comparar arquivos
    Write-Host "`n[ANALISANDO ARQUIVOS]" -ForegroundColor Green
    $global:uniqueFiles = @()
    $totalFolder1 = $global:folder1Files.Count
    $processedFolder1 = 0
    $compareStart = [DateTime]::Now
    
    # Criar um HashSet para pesquisa rápida
    $folder2FilePathsHash = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $global:folder2Files) {
        $relativePath = $file.FullName.Substring($Folder2Path.Length).TrimStart('\')
        [void]$folder2FilePathsHash.Add($relativePath)
    }
    
    foreach ($folder1File in $global:folder1Files) {
        $processedFolder1++
        
        # Exibir a cada 1000 arquivos processados para reduzir sobrecarga de tela
        if ($processedFolder1 % 1000 -eq 0 -or $processedFolder1 -eq 1 -or $processedFolder1 -eq $totalFolder1) {
            $status = "Arquivos únicos: $($global:uniqueFiles.Count) encontrados até agora"
            Show-AdvancedProgress -Stage "Análise" -Current $processedFolder1 -Total $totalFolder1 -StartTime $compareStart -Status $status
        }
        
        $relativePath = $folder1File.FullName.Substring($Folder1Path.Length).TrimStart('\')
        
        if (-not $folder2FilePathsHash.Contains($relativePath)) {
            # CORREÇÃO: Formatar tamanho com unidade apropriada e garantir precisão do tamanho
            $tamanho = $folder1File.Length
            $tamanhoFormatado = if ($tamanho -ge 1GB) {
                "{0:N2} GB" -f ($tamanho / 1GB)
            } elseif ($tamanho -ge 1MB) {
                "{0:N2} MB" -f ($tamanho / 1MB)
            } elseif ($tamanho -ge 1KB) {
                "{0:N2} KB" -f ($tamanho / 1KB)
            } else {
                "{0:N0} bytes" -f $tamanho
            }
            
            $global:uniqueFiles += [PSCustomObject]@{
                'Nome do Arquivo' = $folder1File.Name
                'Caminho Completo' = $folder1File.FullName
                'Tamanho' = $tamanhoFormatado
            }
        }
    }
    
    # Garantir atualização final
    Show-AdvancedProgress -Stage "Análise" -Current $totalFolder1 -Total $totalFolder1 -StartTime $compareStart
    
    # Gerar relatório HTML se solicitado
    if ($global:uniqueFiles.Count -gt 0) {
        if (-not [string]::IsNullOrWhiteSpace($HTMLReport)) {
            # Calcular tempo de execução mas não exibir a menos que ShowDebug seja verdadeiro
            $currentTime = [DateTime]::Now
            $totalExecutionTime = $currentTime - $startTime
            
            # Exibir mensagem de debug somente se solicitado
            if ($ShowDebug) {
                Write-Host "`n[DEBUG] Tempo de execução antes de gerar relatório: $totalExecutionTime" -ForegroundColor Magenta
            }
            
            # Passar o parâmetro ShowDebug para Export-HTMLReport
            Export-HTMLReport -UniqueFiles $global:uniqueFiles -Folder1Path $Folder1Path -Folder2Path $Folder2Path `
                             -OutputHTMLFile $HTMLReport -Folder1Count $global:folder1Files.Count `
                             -Folder2Count $global:folder2Files.Count -StartTime $startTime
            
            Write-Host "`n[RELATÓRIO HTML]" -ForegroundColor Green
            Write-Host "└─ Relatório salvo em: $HTMLReport" -ForegroundColor White
        }
    }
    else {
        Write-Host "`n[RESULTADO]" -ForegroundColor Green
        Write-Host "Nenhum arquivo exclusivo encontrado na Pasta 1." -ForegroundColor White
    }
    
    # Exibir fim
    Write-Host "`n[OPERAÇÃO CONCLUÍDA]" -ForegroundColor Cyan
    Write-Host "Tempo total de execução: " -NoNewline -ForegroundColor DarkGray
    $totalTime = [DateTime]::Now - $startTime
    
    # Formatar o tempo final no mesmo formato usado no relatório HTML
    $hours = [Math]::Floor($totalTime.TotalHours)
    $minutes = $totalTime.Minutes
    $seconds = $totalTime.Seconds
    
    # Arredondar para cima caso seja menor que 1 segundo
    if (($totalTime.TotalSeconds -gt 0) -and ($seconds -eq 0)) {
        $seconds = 1
    }
    
    $formattedTime = "{0}h {1:D2}m {2:D2}s" -f $hours, $minutes, $seconds
    Write-Host $formattedTime -ForegroundColor Yellow
}

# Configurações de exemplo (podem ser alteradas conforme necessário)
$outputDir = "C:\temp\COMPARAÇÕES"  # Pasta onde serão salvos os relatórios

# Definir os pares de pastas para comparação
$folderPairs = @(
    # Par 1: Mkt Edição vs Mkt Edição
    @{
        Folder1 = "C:\Users\mathews"
        Folder2 = "C:\Users\mathews"
    }
)

# Executar a comparação com geração automática de nomes
Compare-FolderPairs -FolderPairs $folderPairs -OutputDir $outputDir
