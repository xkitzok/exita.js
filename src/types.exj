export interface ExitaModule {
  name: string;
  headerPath: string;
  sourcePath: string;
  exports: ExitaExport[];
}

export interface ExitaExport {
  kind: 'function' | 'variable' | 'interface';
  name: string;
  typeAnnotation?: string;
  params?: ExitaParam[];
  returnType?: string;
  isSignal?: boolean;
  defaultValues?: Record<string, string>;
}

export interface ExitaParam {
  name: string;
  typeAnnotation?: string;
  defaultValue?: string;
}

export interface CompilerOptions {
  entry: string;
  outDir: string;
  generateHeaders: boolean;
  generateJS: boolean;
  generateDts: boolean;
  watch: boolean;
}
